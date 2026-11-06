unit Atlas.Common.Pascal.CompilerSwitches;

// Wirksame Compiler-Schalter an einer Stelle (#558), aus einem Lauf des
// Präprozessors (#15):
//   - Schalter R, Q, O, C, I (Bereichs- und Überlaufprüfung, Optimierung,
//     Assertions, I/O-Prüfung): Stand aus der .dproj der aktiven
//     Konfiguration ("$R+" in den Defines, "*" = Vorgabe des Compilers), dann
//     jede wirksame lokale Direktive vor der Stelle ({$R-}, {$R-,Q+},
//     {$RANGECHECKS OFF}).
//   - Ausrichtung A: DCC_Alignment bzw. 8, dann {$A+} (8), {$A-} (1), {$A4},
//     {$ALIGN 4}, {$ALIGN ON|OFF}.
//   - Hinweise und Warnungen: DCC_Hints, DCC_Warnings (Vorgabe an), dann
//     {$HINTS OFF}, {$WARNINGS OFF}.
//   - Einzelne Warnungen: DCC_<Bezeichner> = false bzw. error in der .dproj,
//     dann {$WARN Bezeichner OFF|ON|ERROR|DEFAULT}. Gezeigt werden die
//     abgeschalteten und die als Fehler gemeldeten.
//   - {$PUSHOPT}/{$POPOPT} sichern bzw. stellen alle diese Stände wieder her.
//   - Bedingte Symbole: Projekt und Compiler, dann wirksame $DEFINE/$UNDEF.
// Direktiven aus Include-Dateien zählen an der Stelle ihrer $I-Direktive,
// Direktiven in inaktiven Zweigen gar nicht. Herkunft je Wert: Vorgabe des
// Compilers, Projektoption (Name der Eigenschaft), Direktive mit Zeile bzw.
// Include-Datei mit Zeile. Abweichend heißt: anders als in der .dproj.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor;

type
  {$SCOPEDENUMS ON}
  TSwitchOriginKind = (Default, Project, Directive, Include);
  {$SCOPEDENUMS OFF}

  TSwitchOrigin = record
    Kind: TSwitchOriginKind;
    /// <summary>Eigenschaft der .dproj ("DCC_RangeChecking"), Direktive ("{$R-}") bzw. Herkunft eines Symbols
    /// ("Konfiguration Debug (.dproj)"); '' bei Default ohne Eigenschaft.</summary>
    Text: string;
    /// <summary>Datei der Direktive bzw. Include-Datei; '' sonst.</summary>
    FileName: string;
    /// <summary>Zeile der Direktive, 0-basiert; -1 ohne.</summary>
    Line: Integer;
    class function Make(AKind: TSwitchOriginKind; const AText: string): TSwitchOrigin; static;
  end;

  TSwitchEntry = record
    /// <summary>"R", "A", "HINTS", "WARNINGS", Bezeichner einer Warnung oder Symbol.</summary>
    Name: string;
    /// <summary>Langer Name ("RANGECHECKS", "ALIGN"); '' sonst.</summary>
    LongName: string;
    /// <summary>"+", "-", "1" … "16", "ON", "OFF", "ERROR"; '' bei Symbolen.</summary>
    Value: string;
    /// <summary>Stand ohne lokale Direktiven (.dproj bzw. Vorgabe).</summary>
    ProjectValue: string;
    Origin: TSwitchOrigin;
    function Deviates: Boolean;
  end;

  TSwitchEntries = TArray<TSwitchEntry>;

  /// <summary>Herkunft eines Symbols am Dateianfang.</summary>
  TSwitchDefineOrigin = record
    Name: string;
    Origin: TSwitchOrigin;
    class function Create(const AName: string; const AOrigin: TSwitchOrigin): TSwitchDefineOrigin; static;
  end;

  TCompilerSwitchInput = record
    /// <summary>Symbole des Projekts samt Schalterständen ("$R+", "$R-*").</summary>
    Defines: TArray<string>;
    /// <summary>Herkunft der Symbole; fehlt eines, gilt „Projektoption“.</summary>
    DefineOrigins: TArray<TSwitchDefineOrigin>;
    /// <summary>Eigenschaften der .dproj (aktive Konfiguration und Plattform).</summary>
    Properties: TArray<TPair<string, string>>;
  end;

  TCompilerSwitchState = record
    /// <summary>R, Q, O, C, I, A, D, L in dieser Reihenfolge (D und L für #840).</summary>
    Switches: TSwitchEntries;
    Hints: TSwitchEntry;
    Warnings: TSwitchEntry;
    /// <summary>Abgeschaltete (OFF) und als Fehler gemeldete (ERROR) Warnungen, nach Namen.</summary>
    Warns: TSwitchEntries;
    /// <summary>Aktive Symbole nach Namen.</summary>
    Defines: TSwitchEntries;
    /// <summary>Nur Abweichungen von der .dproj: „R− Q− HINTS OFF“; '' ohne.</summary>
    function Summary: string;
  end;

  TCompilerSwitches = record
  public const
    /// <summary>Gezeigte Schalter in Reihenfolge.</summary>
    cLetters = 'RQOCIADL';
    cAlignProperty = 'DCC_Alignment';
    cHintsProperty = 'DCC_Hints';
    cWarningsProperty = 'DCC_Warnings';
  public
    /// <summary>Stand an APosition der Hauptdatei von AProcessed.</summary>
    class function At(const AProcessed: TPreprocessorResult; const APosition: TTextPosition;
      const AInput: TCompilerSwitchInput): TCompilerSwitchState; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Pascal.DirectiveNames;

type
  /// <summary>Alle Stände während des Nachspielens; Kopie für {$PUSHOPT}.</summary>
  TReplay = class
  public
    Switches: TDictionary<string, TSwitchEntry>;
    Warns: TDictionary<string, TSwitchEntry>;
    constructor Create;
    destructor Destroy; override;
    function Copy: TReplay;
  end;

const
  cMinusSign = #$2212;

{ TSwitchOrigin }

class function TSwitchOrigin.Make(AKind: TSwitchOriginKind; const AText: string): TSwitchOrigin;
begin
  Result.Kind := AKind;
  Result.Text := AText;
  Result.FileName := '';
  Result.Line := -1;
end;

{ TSwitchEntry }

function TSwitchEntry.Deviates: Boolean;
begin
  Result := not SameText(Value, ProjectValue);
end;

{ TSwitchDefineOrigin }

class function TSwitchDefineOrigin.Create(const AName: string; const AOrigin: TSwitchOrigin): TSwitchDefineOrigin;
begin
  Result.Name := AName;
  Result.Origin := AOrigin;
end;

{ TReplay }

constructor TReplay.Create;
begin
  inherited Create;
  Switches := TDictionary<string, TSwitchEntry>.Create;
  Warns := TDictionary<string, TSwitchEntry>.Create;
end;

destructor TReplay.Destroy;
begin
  Warns.Free;
  Switches.Free;
  inherited Destroy;
end;

function TReplay.Copy: TReplay;
var
  mPair: TPair<string, TSwitchEntry>;
begin
  Result := TReplay.Create;
  for mPair in Switches do
  begin
    Result.Switches.Add(mPair.Key, mPair.Value);
  end;
  for mPair in Warns do
  begin
    Result.Warns.Add(mPair.Key, mPair.Value);
  end;
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function PropertyValue(const AProperties: TArray<TPair<string, string>>; const AName: string;
  out AValue: string): Boolean;
var
  mPair: TPair<string, string>;
begin
  for mPair in AProperties do
  begin
    if SameText(mPair.Key, AName) then
    begin
      AValue := LowerCase(Trim(mPair.Value));
      Exit(True);
    end;
  end;
  AValue := '';
  Result := False;
end;

function LongNameOf(ALetter: Char): string;
begin
  case ALetter of
    'R': Result := 'RANGECHECKS';
    'Q': Result := 'OVERFLOWCHECKS';
    'O': Result := 'OPTIMIZATION';
    'C': Result := 'ASSERTIONS';
    'I': Result := 'IOCHECKS';
    'A': Result := 'ALIGN';
    'D': Result := 'DEBUGINFO';
    'L': Result := 'LOCALSYMBOLS';
  else
    Result := '';
  end;
end;

/// <summary>"1", "2", "4", "8", "16" für AText; '' bei anderen Werten.</summary>
function AlignValue(const AText: string): string;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  if (mText = 'on') or (mText = '+') or (mText = 'true') then
  begin
    Result := '8';
  end
  else if (mText = 'off') or (mText = '-') or (mText = 'false') then
  begin
    Result := '1';
  end
  else if (mText = '1') or (mText = '2') or (mText = '4') or (mText = '8') or (mText = '16') then
  begin
    Result := mText;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Ausrichtung aus der .dproj, sonst 8.</summary>
function AlignSwitch(const AInput: TCompilerSwitchInput): TSwitchEntry;
var
  mValue: string;
begin
  Result := Default(TSwitchEntry);
  Result.Value := '8';
  Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, '');
  if PropertyValue(AInput.Properties, TCompilerSwitches.cAlignProperty, mValue) and (AlignValue(mValue) <> '') then
  begin
    Result.Value := AlignValue(mValue);
    Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, TCompilerSwitches.cAlignProperty);
  end;
end;

/// <summary>Ist ADefine ein Schaltereintrag für ALetter ("$R+" aus der .dproj, "$R-*" Vorgabe des Compilers
/// ohne Eintrag dort, #847)? AValue: "+" oder "-".</summary>
function SwitchDefine(const ADefine: string; ALetter: Char; out AValue: Char; out AIsDefault: Boolean): Boolean;
var
  mEntry: string;
begin
  AValue := #0;
  AIsDefault := False;
  if not TPascalPreprocessor.IsSwitchEntry(ADefine) then
  begin
    Exit(False);
  end;
  mEntry := Copy(Trim(ADefine), 2, MaxInt);
  AIsDefault := EndsStr('*', mEntry);
  if AIsDefault then
  begin
    mEntry := Copy(mEntry, 1, Length(mEntry) - 1);
  end;
  Result := (Length(mEntry) = 2) and (UpCase(mEntry[1]) = ALetter) and CharInSet(mEntry[2], ['+', '-']);
  if Result then
  begin
    AValue := mEntry[2];
  end;
end;

/// <summary>Schalter ALetter (außer A) aus Vorgabe und Symbolen des Projekts.</summary>
function FlagSwitch(const AInput: TCompilerSwitchInput; ALetter: Char): TSwitchEntry;
var
  mDefine: string;
  mValue: Char;
  mIsDefault: Boolean;
begin
  Result := Default(TSwitchEntry);
  Result.Value := TPascalPreprocessor.SwitchDefault(ALetter);
  Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, TPascalPreprocessor.SwitchProperty(ALetter));
  for mDefine in AInput.Defines do
  begin
    if SwitchDefine(mDefine, ALetter, mValue, mIsDefault) then
    begin
      Result.Value := mValue;
      if not mIsDefault then
      begin
        Result.Origin.Kind := TSwitchOriginKind.Project;
      end;
    end;
  end;
end;

/// <summary>Schalter HINTS bzw. WARNINGS aus der .dproj.</summary>
function MessageSwitch(const AInput: TCompilerSwitchInput; const AName: string): TSwitchEntry;
var
  mProp, mValue: string;
begin
  Result := Default(TSwitchEntry);
  Result.Name := AName;
  Result.Value := 'ON';
  mProp := TCompilerSwitches.cWarningsProperty;
  if AName = 'HINTS' then
  begin
    mProp := TCompilerSwitches.cHintsProperty;
  end;
  Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, '');
  if PropertyValue(AInput.Properties, mProp, mValue) and ((mValue = 'true') or (mValue = 'false')) then
  begin
    if mValue = 'false' then
    begin
      Result.Value := 'OFF';
    end;
    Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, mProp);
  end;
  Result.ProjectValue := Result.Value;
end;

/// <summary>Einzelne Warnungen: &lt;DCC_SYMBOL_DEPRECATED&gt;false&lt;/DCC_SYMBOL_DEPRECATED&gt; bzw. error.</summary>
procedure AddProjectWarns(const AInput: TCompilerSwitchInput; AReplay: TReplay);
var
  mEntry, mValue: string;
  mSwitch: TSwitchEntry;
begin
  for mEntry in TDirectiveNames.Warnings do
  begin
    if not PropertyValue(AInput.Properties, 'DCC_' + mEntry, mValue) or
      ((mValue <> 'false') and (mValue <> 'error')) then
    begin
      Continue;
    end;
    mSwitch := Default(TSwitchEntry);
    mSwitch.Name := mEntry;
    mSwitch.Value := 'ERROR';
    if mValue = 'false' then
    begin
      mSwitch.Value := 'OFF';
    end;
    mSwitch.ProjectValue := mSwitch.Value;
    mSwitch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, 'DCC_' + mEntry);
    AReplay.Warns.AddOrSetValue(mEntry, mSwitch);
  end;
end;

/// <summary>Projektstand der Schalter (ohne lokale Direktiven).</summary>
procedure ProjectSwitches(const AInput: TCompilerSwitchInput; AReplay: TReplay);
var
  mLetter: Char;
  mEntry: string;
  mSwitch: TSwitchEntry;
  mIndex: Integer;
begin
  for mIndex := 1 to Length(TCompilerSwitches.cLetters) do
  begin
    mLetter := TCompilerSwitches.cLetters[mIndex];
    if mLetter = 'A' then
    begin
      mSwitch := AlignSwitch(AInput);
    end
    else
    begin
      mSwitch := FlagSwitch(AInput, mLetter);
    end;
    mSwitch.Name := mLetter;
    mSwitch.LongName := LongNameOf(mLetter);
    mSwitch.ProjectValue := mSwitch.Value;
    AReplay.Switches.AddOrSetValue(mLetter, mSwitch);
  end;
  for mEntry in TArray<string>.Create('HINTS', 'WARNINGS') do
  begin
    AReplay.Switches.AddOrSetValue(mEntry, MessageSwitch(AInput, mEntry));
  end;
  AddProjectWarns(AInput, AReplay);
end;

/// <summary>Name und Rest einer Direktive ("WARN SYMBOL_DEPRECATED OFF" → "WARN", "SYMBOL_DEPRECATED OFF").
/// </summary>
procedure Split(const ABody: string; out AName, AArgument: string);
begin
  AName := UpperCase(TDirectiveNames.LeadingName(ABody));
  AArgument := Trim(Copy(ABody, Length(AName) + 1, MaxInt));
end;

procedure SetSwitch(AReplay: TReplay; const AName, AValue: string; const AOrigin: TSwitchOrigin);
var
  mSwitch: TSwitchEntry;
begin
  if not AReplay.Switches.TryGetValue(AName, mSwitch) then
  begin
    Exit;
  end;
  mSwitch.Value := AValue;
  mSwitch.Origin := AOrigin;
  AReplay.Switches[AName] := mSwitch;
end;

procedure SetWarn(AReplay: TReplay; AProject: TReplay; const AName, AState: string; const AOrigin: TSwitchOrigin);
var
  mSwitch, mKnown: TSwitchEntry;
  mName: string;
begin
  mName := UpperCase(AName);
  if not AProject.Warns.TryGetValue(mName, mKnown) then
  begin
    mKnown := Default(TSwitchEntry);
    mKnown.Name := mName;
    mKnown.ProjectValue := 'ON';
  end;
  mSwitch := mKnown;
  if AState = 'DEFAULT' then
  begin
    // Zurück zum Stand des Projekts.
    if AProject.Warns.ContainsKey(mName) then
    begin
      AReplay.Warns.AddOrSetValue(mName, mKnown);
    end
    else
    begin
      AReplay.Warns.Remove(mName);
    end;
    Exit;
  end;
  mSwitch.Value := AState;
  mSwitch.Origin := AOrigin;
  AReplay.Warns.AddOrSetValue(mName, mSwitch);
end;

/// <summary>{$WARN Name ON|OFF|ERROR|DEFAULT}.</summary>
procedure ApplyWarn(AReplay, AProject: TReplay; const AArgument: string; const AOrigin: TSwitchOrigin);
var
  mWords: TArray<string>;
  mState: string;
begin
  mWords := AArgument.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  if Length(mWords) <> 2 then
  begin
    Exit;
  end;
  mState := UpperCase(mWords[1]);
  if MatchStr(mState, ['ON', 'OFF', 'ERROR', 'DEFAULT']) then
  begin
    SetWarn(AReplay, AProject, mWords[0], mState, AOrigin);
  end;
end;

/// <summary>{$HINTS ON|OFF}, {$WARNINGS ON|OFF}.</summary>
procedure ApplyMessages(AReplay: TReplay; const AName, AArgument: string; const AOrigin: TSwitchOrigin);
begin
  if SameText(AArgument, 'ON') or SameText(AArgument, 'OFF') then
  begin
    SetSwitch(AReplay, AName, UpperCase(AArgument), AOrigin);
  end;
end;

/// <summary>{$ALIGN 8}.</summary>
procedure ApplyAlign(AReplay: TReplay; const AArgument: string; const AOrigin: TSwitchOrigin);
var
  mValue: string;
begin
  mValue := AlignValue(AArgument);
  if mValue <> '' then
  begin
    SetSwitch(AReplay, 'A', mValue, AOrigin);
  end;
end;

/// <summary>Lange Form eines Schalters ({$RANGECHECKS ON}).</summary>
procedure ApplyLong(AReplay: TReplay; ALetter: Char; const AArgument: string; const AOrigin: TSwitchOrigin);
begin
  if SameText(AArgument, 'ON') then
  begin
    SetSwitch(AReplay, ALetter, '+', AOrigin);
  end
  else if SameText(AArgument, 'OFF') then
  begin
    SetSwitch(AReplay, ALetter, '-', AOrigin);
  end;
end;

/// <summary>Ein Teil eines Kurzschalters ("R-", "A4") als Buchstabe und Wert; False bei anderem Text.</summary>
function ShortChange(const APart: string; out AChange: TPair<string, string>): Boolean;
var
  mValue: string;
  mLetter: Char;
begin
  AChange := TPair<string, string>.Create('', '');
  mValue := Trim(APart);
  if Length(mValue) < 2 then
  begin
    Exit(False);
  end;
  mLetter := UpCase(mValue[1]);
  if mLetter = 'A' then
  begin
    AChange := TPair<string, string>.Create('A', AlignValue(Copy(mValue, 2, MaxInt)));
    Result := AChange.Value <> '';
  end
  else
  begin
    AChange := TPair<string, string>.Create(mLetter, Copy(mValue, 2, MaxInt));
    Result := (Length(mValue) = 2) and CharInSet(mValue[2], ['+', '-']);
  end;
end;

/// <summary>Kurzschalter {$R-}, {$R-,Q+}, {$A4}; {$R Datei.res} oder {$I datei} ändern nichts.</summary>
procedure ApplyShort(AReplay: TReplay; const ABody: string; const AOrigin: TSwitchOrigin);
var
  mChanges: TArray<TPair<string, string>>;
  mChange: TPair<string, string>;
  mPart: string;
begin
  mChanges := nil;
  for mPart in ABody.Split([',']) do
  begin
    if not ShortChange(mPart, mChange) then
    begin
      Exit;
    end;
    mChanges := mChanges + [mChange];
  end;
  for mChange in mChanges do
  begin
    SetSwitch(AReplay, mChange.Key, mChange.Value, AOrigin);
  end;
end;

/// <summary>Wirkung der Direktive ABody auf AReplay; andere Direktiven ändern nichts.</summary>
procedure Apply(AReplay, AProject: TReplay; const ABody: string; const AOrigin: TSwitchOrigin);
var
  mName, mArgument: string;
  mLetter: Char;
begin
  Split(ABody, mName, mArgument);
  if (mName = 'HINTS') or (mName = 'WARNINGS') then
  begin
    ApplyMessages(AReplay, mName, mArgument, AOrigin);
  end
  else if mName = 'WARN' then
  begin
    ApplyWarn(AReplay, AProject, mArgument, AOrigin);
  end
  else if mName = 'ALIGN' then
  begin
    ApplyAlign(AReplay, mArgument, AOrigin);
  end
  else if TPascalPreprocessor.LongSwitchLetter(mName, mLetter) then
  begin
    ApplyLong(AReplay, mLetter, mArgument, AOrigin);
  end
  else
  begin
    ApplyShort(AReplay, ABody, AOrigin);
  end;
end;

function SortedEntries(const AValues: TEnumerable<TSwitchEntry>): TSwitchEntries;
var
  mEntry: TSwitchEntry;
  mList: TList<TSwitchEntry>;
begin
  mList := TList<TSwitchEntry>.Create;
  try
    for mEntry in AValues do
    begin
      mList.Add(mEntry);
    end;
    // Namen sind eindeutig: die Sortierung ist eindeutig.
    mList.Sort(TComparer<TSwitchEntry>.Construct(
      function(const ALeft, ARight: TSwitchEntry): Integer
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function OriginOf(const AProcessed: TPreprocessorResult; AFileIndex: Integer; const ARange: TTextRange;
  const AText: string): TSwitchOrigin;
begin
  if AFileIndex = 0 then
  begin
    Result := TSwitchOrigin.Make(TSwitchOriginKind.Directive, AText);
  end
  else
  begin
    Result := TSwitchOrigin.Make(TSwitchOriginKind.Include, AText);
  end;
  if (AFileIndex >= 0) and (AFileIndex < Length(AProcessed.Files)) then
  begin
    Result.FileName := AProcessed.Files[AFileIndex];
  end;
  Result.Line := ARange.StartPos.Line;
end;

/// <summary>Stand der Schalter vor APosition: Projektstand AProject, dann die Direktiven davor mit
/// {$PUSHOPT}/{$POPOPT}. Der Aufrufer gibt das Ergebnis frei.</summary>
function ReplayAt(const AProcessed: TPreprocessorResult; const APosition: TTextPosition; AProject: TReplay): TReplay;
var
  mStack: TObjectStack<TReplay>;
  mSite: TDirectiveSite;
  mName, mArgument: string;
begin
  Result := AProject.Copy;
  mStack := TObjectStack<TReplay>.Create(True);
  try
    for mSite in AProcessed.DirectiveSites do
    begin
      if not Before(mSite.RootPos, APosition) then
      begin
        Continue;
      end;
      Split(mSite.Body, mName, mArgument);
      if mName = 'PUSHOPT' then
      begin
        mStack.Push(Result.Copy);
      end
      else if (mName = 'POPOPT') and (mStack.Count > 0) then
      begin
        Result.Free;
        Result := mStack.Extract;
      end
      else if mName <> 'POPOPT' then
      begin
        Apply(Result, AProject, mSite.Body, OriginOf(AProcessed, mSite.FileIndex, mSite.Range,
          '{$' + mSite.Body + '}'));
      end;
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Symbol ADefine des Projekts mit seiner Herkunft aus AInput.DefineOrigins.</summary>
function ProjectDefine(const AInput: TCompilerSwitchInput; const ADefine: string): TSwitchEntry;
var
  mOrigin: TSwitchDefineOrigin;
begin
  Result := Default(TSwitchEntry);
  Result.Name := UpperCase(Trim(ADefine));
  Result.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, '');
  for mOrigin in AInput.DefineOrigins do
  begin
    if SameText(mOrigin.Name, Result.Name) then
    begin
      Result.Origin := mOrigin.Origin;
    end;
  end;
end;

/// <summary>Symbole vor APosition: Projekt und Compiler, dann $DEFINE/$UNDEF vor der Stelle.</summary>
function DefinesAt(const AProcessed: TPreprocessorResult; const APosition: TTextPosition;
  const AInput: TCompilerSwitchInput): TSwitchEntries;
var
  mDefines: TDictionary<string, TSwitchEntry>;
  mDefine: string;
  mSite: TDefineSite;
  mEntry: TSwitchEntry;
begin
  mDefines := TDictionary<string, TSwitchEntry>.Create;
  try
    for mDefine in AInput.Defines do
    begin
      if not TPascalPreprocessor.IsSwitchEntry(mDefine) and (Trim(mDefine) <> '') then
      begin
        mEntry := ProjectDefine(AInput, mDefine);
        mDefines.AddOrSetValue(mEntry.Name, mEntry);
      end;
    end;
    for mSite in AProcessed.DefineSites do
    begin
      if not Before(mSite.RootPos, APosition) then
      begin
        Continue;
      end;
      if mSite.Undefine then
      begin
        mDefines.Remove(mSite.Name);
        Continue;
      end;
      mEntry := Default(TSwitchEntry);
      mEntry.Name := mSite.Name;
      mEntry.Origin := OriginOf(AProcessed, mSite.FileIndex, mSite.Range, '{$DEFINE ' + mSite.Name + '}');
      mDefines.AddOrSetValue(mEntry.Name, mEntry);
    end;
    Result := SortedEntries(mDefines.Values);
  finally
    mDefines.Free;
  end;
end;

/// <summary>Warnungen, die nicht ON sind, nach Namen sortiert.</summary>
function ChangedWarns(AReplay: TReplay): TSwitchEntries;
var
  mWarn: TSwitchEntry;
begin
  Result := nil;
  for mWarn in SortedEntries(AReplay.Warns.Values) do
  begin
    if mWarn.Value <> 'ON' then
    begin
      Result := Result + [mWarn];
    end;
  end;
end;

{ TCompilerSwitches }

class function TCompilerSwitches.At(const AProcessed: TPreprocessorResult; const APosition: TTextPosition;
  const AInput: TCompilerSwitchInput): TCompilerSwitchState;
var
  mProject, mReplay: TReplay;
  mIndex: Integer;
begin
  Result := Default(TCompilerSwitchState);
  mProject := TReplay.Create;
  mReplay := nil;
  try
    ProjectSwitches(AInput, mProject);
    mReplay := ReplayAt(AProcessed, APosition, mProject);
    for mIndex := 1 to Length(cLetters) do
    begin
      Result.Switches := Result.Switches + [mReplay.Switches[cLetters[mIndex]]];
    end;
    Result.Hints := mReplay.Switches['HINTS'];
    Result.Warnings := mReplay.Switches['WARNINGS'];
    Result.Warns := ChangedWarns(mReplay);
    Result.Defines := DefinesAt(AProcessed, APosition, AInput);
  finally
    mReplay.Free;
    mProject.Free;
  end;
end;

{ TCompilerSwitchState }

/// <summary>Kurzform eines abweichenden Schalters ("A4", "R−", "Q+").</summary>
function SwitchSummary(const AEntry: TSwitchEntry): string;
begin
  if AEntry.Name = 'A' then
  begin
    Result := 'A' + AEntry.Value;
  end
  else if AEntry.Value = '-' then
  begin
    Result := AEntry.Name + cMinusSign;
  end
  else
  begin
    Result := AEntry.Name + AEntry.Value;
  end;
end;

/// <summary>Abweichende Warnungen: eine mit Namen, mehrere als Anzahl; '' ohne.</summary>
function WarnsSummary(const AWarns: TSwitchEntries): string;
var
  mEntry: TSwitchEntry;
  mCount: Integer;
begin
  Result := '';
  mCount := 0;
  for mEntry in AWarns do
  begin
    if mEntry.Deviates then
    begin
      Inc(mCount);
      Result := 'WARN ' + mEntry.Name + ' ' + mEntry.Value;
    end;
  end;
  if mCount > 1 then
  begin
    Result := Format('WARN %d×', [mCount]);
  end;
end;

function TCompilerSwitchState.Summary: string;
var
  mEntry: TSwitchEntry;
  mParts: TArray<string>;
  mWarn: string;
begin
  mParts := nil;
  for mEntry in Switches do
  begin
    if mEntry.Deviates then
    begin
      mParts := mParts + [SwitchSummary(mEntry)];
    end;
  end;
  if Hints.Deviates then
  begin
    mParts := mParts + ['HINTS ' + Hints.Value];
  end;
  if Warnings.Deviates then
  begin
    mParts := mParts + ['WARNINGS ' + Warnings.Value];
  end;
  mWarn := WarnsSummary(Warns);
  if mWarn <> '' then
  begin
    mParts := mParts + [mWarn];
  end;
  Result := String.Join(' ', mParts);
end;

end.
