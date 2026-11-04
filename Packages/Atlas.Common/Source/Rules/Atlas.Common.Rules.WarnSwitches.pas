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

/// <summary>Text zwischen {$ und } bzw. (*$ und *).</summary>
function DirectiveBody(const AText: string): string;
begin
  if StartsStr('(*', AText) then
  begin
    Result := Copy(AText, 4, Length(AText) - 5);
  end
  else
  begin
    Result := Copy(AText, 3, Length(AText) - 3);
  end;
end;

/// <summary>ON, ERROR, OFF und bei $WARN auch DEFAULT; False bei anderem Wert.</summary>
function WarnValueOf(const AValue: string; AIsWarn: Boolean; out AResult: TRuleWarnSwitches.TWarnValue): Boolean;
begin
  Result := True;
  if AValue = 'ON' then
  begin
    AResult := TRuleWarnSwitches.TWarnValue.SetOn;
  end
  else if AValue = 'ERROR' then
  begin
    AResult := TRuleWarnSwitches.TWarnValue.SetError;
  end
  else if AValue = 'OFF' then
  begin
    AResult := TRuleWarnSwitches.TWarnValue.SetOff;
  end
  else if (AValue = 'DEFAULT') and AIsWarn then
  begin
    AResult := TRuleWarnSwitches.TWarnValue.SetDefault;
  end
  else
  begin
    AResult := TRuleWarnSwitches.TWarnValue.SetDefault;
    Result := False;
  end;
end;

/// <summary>{$WARN SYMBOL_PLATFORM OFF} bzw. (*$WARNINGS OFF*) aus dem Token; False für andere Direktiven und
/// unvollständige Schalter. Offset und Pfad setzt der Aufrufer.</summary>
function SwitchOf(const AToken: TPascalToken; out ASwitch: TRuleWarnSwitches.TWarnSwitch): Boolean;
var
  mName, mValue: string;
  mWords: TArray<string>;
begin
  ASwitch := Default(TRuleWarnSwitches.TWarnSwitch);
  mName := TPascalLexer.DirectiveName(AToken.Text);
  mWords := DirectiveBody(AToken.Text).Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty);
  if (mName = 'WARN') and (Length(mWords) >= 3) then
  begin
    ASwitch.Name := UpperCase(mWords[1]);
    mValue := UpperCase(mWords[2]);
  end
  else if (mName = cWarningsName) and (Length(mWords) >= 2) then
  begin
    mValue := UpperCase(mWords[1]);
  end
  else
  begin
    Exit(False);
  end;
  Result := WarnValueOf(mValue, mName = 'WARN', ASwitch.Value);
end;

procedure TRuleWarnSwitches.ReadSwitches;
var
  mIndex: Integer;
  mSwitch: TWarnSwitch;
begin
  FPaths := TConditionalBranches.Paths(FTokens);
  FSwitches := nil;
  for mIndex := 0 to High(FTokens) do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Directive) and SwitchOf(FTokens[mIndex], mSwitch) then
    begin
      mSwitch.Offset := FTokens[mIndex].Offset;
      mSwitch.Path := TConditionalBranches.PathAt(FPaths, mIndex);
      FSwitches := FSwitches + [mSwitch];
    end;
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

/// <summary>Stand nach einem benannten Schalter; ABase für DEFAULT.</summary>
function NamedState(AValue: TRuleWarnSwitches.TWarnValue; ABase: TRuleWarnState): TRuleWarnState;
begin
  case AValue of
    TRuleWarnSwitches.TWarnValue.SetOn:
      Result := TRuleWarnState.Enabled;
    TRuleWarnSwitches.TWarnValue.SetError:
      Result := TRuleWarnState.AsError;
    TRuleWarnSwitches.TWarnValue.SetOff:
      Result := TRuleWarnState.Disabled;
  else
    Result := ABase;
  end;
end;

/// <summary>Wendet ASwitch an der Stelle mit Pfad APath an: {$WARNINGS} auf AWarnings, {$WARN} auf AState. Ein
/// Schalter, der nicht sicher mit der Stelle übersetzt wird, macht den Stand unbekannt.</summary>
procedure ApplySwitch(const ASwitch: TRuleWarnSwitches.TWarnSwitch; const APath: string; ABase: TRuleWarnState;
  var AState, AWarnings: TRuleWarnState);
var
  mSure: Boolean;
begin
  mSure := TConditionalBranches.Implies(APath, ASwitch.Path);
  if (ASwitch.Name = '') and not mSure then
  begin
    AWarnings := TRuleWarnState.Unknown;
  end
  else if (ASwitch.Name = '') and (ASwitch.Value = TRuleWarnSwitches.TWarnValue.SetOff) then
  begin
    AWarnings := TRuleWarnState.Disabled;
  end
  else if ASwitch.Name = '' then
  begin
    AWarnings := TRuleWarnState.Enabled;
  end
  else if not mSure then
  begin
    AState := TRuleWarnState.Unknown;
  end
  else
  begin
    AState := NamedState(ASwitch.Value, ABase);
  end;
end;

/// <summary>Abgeschaltet schlägt unbekannt, unbekannt schlägt den Stand der Warnung.</summary>
function Combined(AState, AWarnings: TRuleWarnState): TRuleWarnState;
begin
  if (AState = TRuleWarnState.Disabled) or (AWarnings = TRuleWarnState.Disabled) then
  begin
    Result := TRuleWarnState.Disabled;
  end
  else if (AState = TRuleWarnState.Unknown) or (AWarnings = TRuleWarnState.Unknown) then
  begin
    Result := TRuleWarnState.Unknown;
  end
  else
  begin
    Result := AState;
  end;
end;

function TRuleWarnSwitches.StateAt(const AName: string; ADefaultOn: Boolean; ATokenIndex: Integer): TRuleWarnState;
var
  mBase, mState, mWarnings: TRuleWarnState;
  mSwitch: TWarnSwitch;
  mPath, mKey: string;
  mOffset: Integer;
begin
  if (ATokenIndex < 0) or (ATokenIndex > High(FTokens)) then
  begin
    Exit(TRuleWarnState.Unknown);
  end;
  mKey := UpperCase(AName);
  mBase := ProjectState(mKey, ADefaultOn);
  mState := mBase;
  mWarnings := TRuleWarnState.Enabled;
  if ProjectValue(cWarningsName) = 'false' then
  begin
    mWarnings := TRuleWarnState.Disabled;
  end;
  mPath := TConditionalBranches.PathAt(FPaths, ATokenIndex);
  mOffset := FTokens[ATokenIndex].Offset;
  for mSwitch in FSwitches do
  begin
    if mSwitch.Offset >= mOffset then
    begin
      Break;
    end;
    // Ein Schalter im anderen Zweig desselben {$IF} gilt an der Stelle nie.
    if ((mSwitch.Name = '') or (mSwitch.Name = mKey)) and not TConditionalBranches.Exclusive(mPath, mSwitch.Path) then
    begin
      ApplySwitch(mSwitch, mPath, mBase, mState, mWarnings);
    end;
  end;
  Result := Combined(mState, mWarnings);
end;

end.
