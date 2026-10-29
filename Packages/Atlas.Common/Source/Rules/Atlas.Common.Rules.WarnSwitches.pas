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
    FTokens := AContext.Tree.Tokens;
  FProjectWarnings := AContext.ProjectWarnings;
  ReadSwitches;
end;

class function TRuleWarnSwitches.ProjectEntry(const AProperty, AValue: string): string;
var
  mName: string;
begin
  Result := '';
  if not StartsText(cPropertyPrefix, AProperty) then
    Exit;
  mName := UpperCase(Copy(AProperty, Length(cPropertyPrefix) + 1, MaxInt));
  if (mName <> cWarningsName) and (IndexText(mName, TDirectiveNames.Warnings) < 0) then
    Exit;
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
      Continue;
    mName := TPascalLexer.DirectiveName(FTokens[mIndex].Text);
    if (mName <> 'WARN') and (mName <> cWarningsName) then
      Continue;
    // {$WARN SYMBOL_PLATFORM OFF} bzw. (*$WARNINGS OFF*)
    mBody := FTokens[mIndex].Text;
    if StartsStr('(*', mBody) then
      mBody := Copy(mBody, 4, Length(mBody) - 5)
    else
      mBody := Copy(mBody, 3, Length(mBody) - 3);
    mWords := mBody.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
    mSwitch := Default(TWarnSwitch);
    mSwitch.Offset := FTokens[mIndex].Offset;
    mSwitch.Path := TConditionalBranches.PathAt(FPaths, mIndex);
    if mName = 'WARN' then
    begin
      if Length(mWords) < 3 then
        Continue;
      mSwitch.Name := UpperCase(mWords[1]);
      mValue := UpperCase(mWords[2]);
    end
    else
    begin
      if Length(mWords) < 2 then
        Continue;
      mValue := UpperCase(mWords[1]);
    end;
    if mValue = 'ON' then
      mSwitch.Value := TWarnValue.SetOn
    else if mValue = 'ERROR' then
      mSwitch.Value := TWarnValue.SetError
    else if mValue = 'OFF' then
      mSwitch.Value := TWarnValue.SetOff
    else if (mValue = 'DEFAULT') and (mName = 'WARN') then
      mSwitch.Value := TWarnValue.SetDefault
    else
      Continue;
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
    if StartsText(mPrefix, mEntry) then
      Result := LowerCase(Copy(mEntry, Length(mPrefix) + 1, MaxInt));
end;

function TRuleWarnSwitches.MentionsAny(const ANames: array of string): Boolean;
var
  mSwitch: TWarnSwitch;
begin
  for mSwitch in FSwitches do
    if (mSwitch.Name <> '') and MatchText(mSwitch.Name, ANames) then
      Exit(True);
  Result := False;
end;

function TRuleWarnSwitches.ProjectState(const AName: string; ADefaultOn: Boolean): TRuleWarnState;
var
  mValue: string;
begin
  mValue := ProjectValue(AName);
  if mValue = 'true' then
    Result := TRuleWarnState.Enabled
  else if mValue = 'error' then
    Result := TRuleWarnState.AsError
  else if mValue = 'false' then
    Result := TRuleWarnState.Disabled
  else if ADefaultOn then
    Result := TRuleWarnState.Enabled
  else
    Result := TRuleWarnState.Disabled;
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
    mWarnings := TRuleWarnState.Disabled
  else
    mWarnings := TRuleWarnState.Enabled;
  if (ATokenIndex < 0) or (ATokenIndex > High(FTokens)) then
    Exit(TRuleWarnState.Unknown);
  mPath := TConditionalBranches.PathAt(FPaths, ATokenIndex);
  mOffset := FTokens[ATokenIndex].Offset;
  for mSwitch in FSwitches do
  begin
    if mSwitch.Offset >= mOffset then
      Break;
    if (mSwitch.Name <> '') and (mSwitch.Name <> mKey) then
      Continue;
    if TConditionalBranches.Exclusive(mPath, mSwitch.Path) then
      Continue;
    if mSwitch.Name = '' then
    begin
      if not TConditionalBranches.Implies(mPath, mSwitch.Path) then
        mWarnings := TRuleWarnState.Unknown
      else if mSwitch.Value = TWarnValue.SetOff then
        mWarnings := TRuleWarnState.Disabled
      else
        mWarnings := TRuleWarnState.Enabled;
      Continue;
    end;
    if not TConditionalBranches.Implies(mPath, mSwitch.Path) then
      mState := TRuleWarnState.Unknown
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
    Exit(TRuleWarnState.Disabled);
  if (mState = TRuleWarnState.Unknown) or (mWarnings = TRuleWarnState.Unknown) then
    Exit(TRuleWarnState.Unknown);
  Result := mState;
end;

end.
