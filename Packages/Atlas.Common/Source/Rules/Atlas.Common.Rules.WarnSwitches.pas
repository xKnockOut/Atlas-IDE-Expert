unit Atlas.Common.Rules.WarnSwitches;

// Stand einer einzelnen Compilerwarnung an einer Stelle für die Regeln der
// Gruppe „Compiler vorab“ (#1018, #1378), wie bei dcc:
//   1. Vorgabe von dcc (an oder aus, je Warnung vom Aufrufer genannt),
//   2. Projektoption der .dproj: DCC_<Bezeichner> = true, false oder error
//      (TRuleContext.ProjectWarnings), DCC_Warnings = false schaltet alle ab,
//   3. {$WARN Bezeichner ON|OFF|ERROR|DEFAULT} und {$WARNINGS ON|OFF} in der
//      Datei vor der Stelle; DEFAULT kehrt zum Stand aus 1. und 2. zurück.
// Ein Schalter im anderen Zweig desselben {$IF} gilt an der Stelle nie; einer,
// der nicht sicher mit der Stelle übersetzt wird, macht den Stand unbekannt.
// Regeln melden nur bei Enabled und AsError.

interface

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Zustand einer Warnung an einer Stelle: an, als Fehler, aus oder nicht sicher bekannt.</summary>
  TRuleWarnState = (Enabled, AsError, Disabled, Unknown);
{$SCOPEDENUMS OFF}

  TRuleWarnSwitches = class
  private type
{$SCOPEDENUMS ON}
    TWarnValue = (SetOn, SetError, SetOff, SetDefault);
{$SCOPEDENUMS OFF}
    /// <summary>Schalter {$WARN Name Wert} bzw. {$WARNINGS Wert} (Name '') an Offset und Zweig Path.</summary>
    TWarnSwitch = record
      Offset: Integer;
      Path: string;
      Name: string;
      Value: TWarnValue;
    end;
  private
    FTokens: TArray<TPascalToken>;
    FPaths: TArray<string>;
    FSwitches: TArray<TWarnSwitch>;
    FProjectWarnings: TArray<string>;
    procedure ReadSwitches;
    function ProjectValue(const AName: string): string;
  public
    constructor Create(const AContext: TRuleContext);
    /// <summary>Stand der Warnung AName (Bezeichner wie SYMBOL_PLATFORM) ohne Schalter der Datei: Vorgabe von dcc
    /// (ADefaultOn) bzw. Projektoption.</summary>
    function ProjectState(const AName: string; ADefaultOn: Boolean): TRuleWarnState;
    /// <summary>Stand der Warnung AName am Token ATokenIndex des Baums.</summary>
    function StateAt(const AName: string; ADefaultOn: Boolean; ATokenIndex: Integer): TRuleWarnState;
    /// <summary>Wie StateAt, für das Token, das an AOffset (0-basiert im Text) oder dahinter beginnt.</summary>
    function StateAtOffset(const AName: string; ADefaultOn: Boolean; AOffset: Integer): TRuleWarnState;
    /// <summary>Steht in der Datei ein {$WARN} für einen der Bezeichner ANames?</summary>
    function MentionsAny(const ANames: array of string): Boolean;
    /// <summary>Meldet dcc die Warnung in diesem Stand (an oder als Fehler)?</summary>
    class function Reported(AState: TRuleWarnState): Boolean; static;
    /// <summary>Eintrag für TRuleContext.ProjectWarnings aus einer Eigenschaft der .dproj ("DCC_SYMBOL_PLATFORM",
    /// "false" ergibt "SYMBOL_PLATFORM=false"; DCC_Warnings ergibt "WARNINGS=…"); '' für andere Eigenschaften.
    /// </summary>
    class function ProjectEntry(const AProperty, AValue: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.ConditionalBranches;

const
  cPropertyPrefix = 'DCC_';
  cWarningsName = 'WARNINGS';

{ TRuleWarnSwitches }

constructor TRuleWarnSwitches.Create(const AContext: TRuleContext);
begin
  inherited Create;
  if AContext.Tree <> nil then
  begin
    FTokens := AContext.Tree.Tokens;
  end;
  FProjectWarnings := AContext.ProjectWarnings;
  ReadSwitches;
end;

class function TRuleWarnSwitches.ProjectEntry(const AProperty, AValue: string): string;
var
  mName: string;
begin
  Result := '';
  if not StartsText(cPropertyPrefix, AProperty) then
  begin
    Exit;
  end;
  mName := UpperCase(Copy(AProperty, Length(cPropertyPrefix) + 1, MaxInt));
  if (mName <> cWarningsName) and (IndexText(mName, TDirectiveNames.Warnings) < 0) then
  begin
    Exit;
  end;
  Result := mName + '=' + LowerCase(Trim(AValue));
end;

class function TRuleWarnSwitches.Reported(AState: TRuleWarnState): Boolean;
begin
  Result := AState in [TRuleWarnState.Enabled, TRuleWarnState.AsError];
end;

procedure TRuleWarnSwitches.ReadSwitches;
var
  mIndex: Integer;
  mName, mBody, mValue: string;
  mWords: TArray<string>;
  mSwitch: TWarnSwitch;
begin
  FPaths := TConditionalBranches.Paths(FTokens);
  FSwitches := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mName := TPascalLexer.DirectiveName(FTokens[mIndex].Text);
    if (mName <> 'WARN') and (mName <> cWarningsName) then
    begin
      Continue;
    end;
    // {$WARN SYMBOL_PLATFORM OFF} bzw. (*$WARNINGS OFF*)
    mBody := FTokens[mIndex].Text;
    if StartsStr('(*', mBody) then
    begin
      mBody := Copy(mBody, 4, Length(mBody) - 5);
    end
    else
    begin
      mBody := Copy(mBody, 3, Length(mBody) - 3);
    end;
    mWords := mBody.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
    mSwitch := Default(TWarnSwitch);
    mSwitch.Offset := FTokens[mIndex].Offset;
    mSwitch.Path := TConditionalBranches.PathAt(FPaths, mIndex);
    if mName = 'WARN' then
    begin
      if Length(mWords) < 3 then
      begin
        Continue;
      end;
      mSwitch.Name := UpperCase(mWords[1]);
      mValue := UpperCase(mWords[2]);
    end
    else
    begin
      if Length(mWords) < 2 then
      begin
        Continue;
      end;
      mValue := UpperCase(mWords[1]);
    end;
    if mValue = 'ON' then
    begin
      mSwitch.Value := TWarnValue.SetOn;
    end
    else if mValue = 'ERROR' then
    begin
      mSwitch.Value := TWarnValue.SetError;
    end
    else if mValue = 'OFF' then
    begin
      mSwitch.Value := TWarnValue.SetOff;
    end
    else if (mValue = 'DEFAULT') and (mName = 'WARN') then
    begin
      mSwitch.Value := TWarnValue.SetDefault;
    end
    else
    begin
      Continue;
    end;
    FSwitches := FSwitches + [mSwitch];
  end;
end;

function TRuleWarnSwitches.ProjectValue(const AName: string): string;
var
  mEntry, mPrefix: string;
begin
  Result := '';
  mPrefix := UpperCase(AName) + '=';
  for mEntry in FProjectWarnings do
  begin
    if StartsText(mPrefix, mEntry) then
    begin
      Result := LowerCase(Copy(mEntry, Length(mPrefix) + 1, MaxInt));
    end;
  end;
end;

function TRuleWarnSwitches.MentionsAny(const ANames: array of string): Boolean;
var
  mSwitch: TWarnSwitch;
begin
  for mSwitch in FSwitches do
  begin
    if (mSwitch.Name <> '') and MatchText(mSwitch.Name, ANames) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TRuleWarnSwitches.ProjectState(const AName: string; ADefaultOn: Boolean): TRuleWarnState;
var
  mValue: string;
begin
  mValue := ProjectValue(AName);
  if mValue = 'true' then
  begin
    Result := TRuleWarnState.Enabled;
  end
  else if mValue = 'error' then
  begin
    Result := TRuleWarnState.AsError;
  end
  else if mValue = 'false' then
  begin
    Result := TRuleWarnState.Disabled;
  end
  else if ADefaultOn then
  begin
    Result := TRuleWarnState.Enabled;
  end
  else
  begin
    Result := TRuleWarnState.Disabled;
  end;
end;

function TRuleWarnSwitches.StateAtOffset(const AName: string; ADefaultOn: Boolean;
  AOffset: Integer): TRuleWarnState;
var
  mLow, mHigh, mMiddle: Integer;
begin
  mLow := 0;
  mHigh := Length(FTokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  Result := StateAt(AName, ADefaultOn, mLow);
end;

function TRuleWarnSwitches.StateAt(const AName: string; ADefaultOn: Boolean; ATokenIndex: Integer): TRuleWarnState;
var
  mBase, mState, mWarnings: TRuleWarnState;
  mSwitch: TWarnSwitch;
  mPath, mKey: string;
  mOffset: Integer;
begin
  mKey := UpperCase(AName);
  mBase := ProjectState(mKey, ADefaultOn);
  mState := mBase;
  if ProjectValue(cWarningsName) = 'false' then
  begin
    mWarnings := TRuleWarnState.Disabled;
  end
  else
  begin
    mWarnings := TRuleWarnState.Enabled;
  end;
  if (ATokenIndex < 0) or (ATokenIndex > High(FTokens)) then
  begin
    Exit(TRuleWarnState.Unknown);
  end;
  mPath := TConditionalBranches.PathAt(FPaths, ATokenIndex);
  mOffset := FTokens[ATokenIndex].Offset;
  for mSwitch in FSwitches do
  begin
    if mSwitch.Offset >= mOffset then
    begin
      Break;
    end;
    if (mSwitch.Name <> '') and (mSwitch.Name <> mKey) then
    begin
      Continue;
    end;
    if TConditionalBranches.Exclusive(mPath, mSwitch.Path) then
    begin
      Continue;
    end;
    if mSwitch.Name = '' then
    begin
      if not TConditionalBranches.Implies(mPath, mSwitch.Path) then
      begin
        mWarnings := TRuleWarnState.Unknown;
      end
      else if mSwitch.Value = TWarnValue.SetOff then
      begin
        mWarnings := TRuleWarnState.Disabled;
      end
      else
      begin
        mWarnings := TRuleWarnState.Enabled;
      end;
      Continue;
    end;
    if not TConditionalBranches.Implies(mPath, mSwitch.Path) then
    begin
      mState := TRuleWarnState.Unknown;
    end
    else
      case mSwitch.Value of
        TWarnValue.SetOn:
          mState := TRuleWarnState.Enabled;
        TWarnValue.SetError:
          mState := TRuleWarnState.AsError;
        TWarnValue.SetOff:
          mState := TRuleWarnState.Disabled;
        TWarnValue.SetDefault:
          mState := mBase;
      end;
  end;
  if (mState = TRuleWarnState.Disabled) or (mWarnings = TRuleWarnState.Disabled) then
  begin
    Exit(TRuleWarnState.Disabled);
  end;
  if (mState = TRuleWarnState.Unknown) or (mWarnings = TRuleWarnState.Unknown) then
  begin
    Exit(TRuleWarnState.Unknown);
  end;
  Result := mState;
end;

end.
