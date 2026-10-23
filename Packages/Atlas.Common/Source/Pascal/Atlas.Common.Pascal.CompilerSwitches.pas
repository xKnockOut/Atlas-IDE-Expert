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
    /// <summary>R, Q, O, C, I, A in dieser Reihenfolge.</summary>
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
    Letters = 'RQOCIA';
    AlignProperty = 'DCC_Alignment';
    HintsProperty = 'DCC_Hints';
    WarningsProperty = 'DCC_Warnings';
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
  MinusSign = #$2212;

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
  Pair: TPair<string, TSwitchEntry>;
begin
  Result := TReplay.Create;
  for Pair in Switches do
    Result.Switches.Add(Pair.Key, Pair.Value);
  for Pair in Warns do
    Result.Warns.Add(Pair.Key, Pair.Value);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character < B.Character));
end;

function PropertyValue(const AProperties: TArray<TPair<string, string>>; const AName: string;
  out AValue: string): Boolean;
var
  Pair: TPair<string, string>;
begin
  for Pair in AProperties do
    if SameText(Pair.Key, AName) then
    begin
      AValue := LowerCase(Trim(Pair.Value));
      Exit(True);
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
  else
    Result := '';
  end;
end;

/// <summary>"1", "2", "4", "8", "16" für AText; '' bei anderen Werten.</summary>
function AlignValue(const AText: string): string;
var
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  if (Text = 'on') or (Text = '+') or (Text = 'true') then
    Result := '8'
  else if (Text = 'off') or (Text = '-') or (Text = 'false') then
    Result := '1'
  else if (Text = '1') or (Text = '2') or (Text = '4') or (Text = '8') or (Text = '16') then
    Result := Text
  else
    Result := '';
end;

/// <summary>Projektstand der Schalter (ohne lokale Direktiven).</summary>
procedure ProjectSwitches(const AInput: TCompilerSwitchInput; AReplay: TReplay);
var
  Letter: Char;
  Define, Entry, Value, Prop: string;
  IsDefault: Boolean;
  Switch: TSwitchEntry;
  Index: Integer;
begin
  for Index := 1 to Length(TCompilerSwitches.Letters) do
  begin
    Letter := TCompilerSwitches.Letters[Index];
    Switch := Default(TSwitchEntry);
    Switch.Name := Letter;
    Switch.LongName := LongNameOf(Letter);
    if Letter = 'A' then
    begin
      Switch.Value := '8';
      Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, '');
      if PropertyValue(AInput.Properties, TCompilerSwitches.AlignProperty, Value) and (AlignValue(Value) <> '') then
      begin
        Switch.Value := AlignValue(Value);
        Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, TCompilerSwitches.AlignProperty);
      end;
    end
    else
    begin
      Switch.Value := TPascalPreprocessor.SwitchDefault(Letter);
      Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, TPascalPreprocessor.SwitchProperty(Letter));
      for Define in AInput.Defines do
      begin
        // "$R+" aus der .dproj, "$R-*" Vorgabe des Compilers ohne Eintrag dort (#847).
        if not TPascalPreprocessor.IsSwitchEntry(Define) then
          Continue;
        Entry := Copy(Trim(Define), 2, MaxInt);
        IsDefault := EndsStr('*', Entry);
        if IsDefault then
          Entry := Copy(Entry, 1, Length(Entry) - 1);
        if (Length(Entry) = 2) and (UpCase(Entry[1]) = Letter) and CharInSet(Entry[2], ['+', '-']) then
        begin
          Switch.Value := Entry[2];
          if not IsDefault then
            Switch.Origin.Kind := TSwitchOriginKind.Project;
        end;
      end;
    end;
    Switch.ProjectValue := Switch.Value;
    AReplay.Switches.AddOrSetValue(Letter, Switch);
  end;
  for Entry in TArray<string>.Create('HINTS', 'WARNINGS') do
  begin
    Switch := Default(TSwitchEntry);
    Switch.Name := Entry;
    Switch.Value := 'ON';
    if Entry = 'HINTS' then
      Prop := TCompilerSwitches.HintsProperty
    else
      Prop := TCompilerSwitches.WarningsProperty;
    Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Default, '');
    if PropertyValue(AInput.Properties, Prop, Value) and ((Value = 'true') or (Value = 'false')) then
    begin
      if Value = 'false' then
        Switch.Value := 'OFF';
      Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, Prop);
    end;
    Switch.ProjectValue := Switch.Value;
    AReplay.Switches.AddOrSetValue(Entry, Switch);
  end;
  // Einzelne Warnungen: <DCC_SYMBOL_DEPRECATED>false</DCC_SYMBOL_DEPRECATED> bzw. error.
  for Entry in TDirectiveNames.Warnings do
    if PropertyValue(AInput.Properties, 'DCC_' + Entry, Value) and ((Value = 'false') or (Value = 'error')) then
    begin
      Switch := Default(TSwitchEntry);
      Switch.Name := Entry;
      if Value = 'false' then
        Switch.Value := 'OFF'
      else
        Switch.Value := 'ERROR';
      Switch.ProjectValue := Switch.Value;
      Switch.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, 'DCC_' + Entry);
      AReplay.Warns.AddOrSetValue(Entry, Switch);
    end;
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
  Switch: TSwitchEntry;
begin
  if not AReplay.Switches.TryGetValue(AName, Switch) then
    Exit;
  Switch.Value := AValue;
  Switch.Origin := AOrigin;
  AReplay.Switches[AName] := Switch;
end;

procedure SetWarn(AReplay: TReplay; AProject: TReplay; const AName, AState: string; const AOrigin: TSwitchOrigin);
var
  Switch, Known: TSwitchEntry;
  Name: string;
begin
  Name := UpperCase(AName);
  if not AProject.Warns.TryGetValue(Name, Known) then
  begin
    Known := Default(TSwitchEntry);
    Known.Name := Name;
    Known.ProjectValue := 'ON';
  end;
  Switch := Known;
  if AState = 'DEFAULT' then
  begin
    // Zurück zum Stand des Projekts.
    if AProject.Warns.ContainsKey(Name) then
      AReplay.Warns.AddOrSetValue(Name, Known)
    else
      AReplay.Warns.Remove(Name);
    Exit;
  end;
  Switch.Value := AState;
  Switch.Origin := AOrigin;
  AReplay.Warns.AddOrSetValue(Name, Switch);
end;

/// <summary>Wirkung der Direktive ABody auf AReplay; andere Direktiven ändern nichts.</summary>
procedure Apply(AReplay, AProject: TReplay; const ABody: string; const AOrigin: TSwitchOrigin);
var
  Name, Argument, Part, Value, State: string;
  Letter: Char;
  Parts: TArray<string>;
  Words: TArray<string>;
  Changes: TArray<TPair<string, string>>;
  Change: TPair<string, string>;
begin
  Split(ABody, Name, Argument);
  if (Name = 'HINTS') or (Name = 'WARNINGS') then
  begin
    if SameText(Argument, 'ON') or SameText(Argument, 'OFF') then
      SetSwitch(AReplay, Name, UpperCase(Argument), AOrigin);
    Exit;
  end;
  if Name = 'WARN' then
  begin
    Words := Argument.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
    if Length(Words) <> 2 then
      Exit;
    State := UpperCase(Words[1]);
    if (State = 'ON') or (State = 'OFF') or (State = 'ERROR') or (State = 'DEFAULT') then
      SetWarn(AReplay, AProject, Words[0], State, AOrigin);
    Exit;
  end;
  if Name = 'ALIGN' then
  begin
    Value := AlignValue(Argument);
    if Value <> '' then
      SetSwitch(AReplay, 'A', Value, AOrigin);
    Exit;
  end;
  if TPascalPreprocessor.LongSwitchLetter(Name, Letter) then
  begin
    if SameText(Argument, 'ON') then
      SetSwitch(AReplay, Letter, '+', AOrigin)
    else if SameText(Argument, 'OFF') then
      SetSwitch(AReplay, Letter, '-', AOrigin);
    Exit;
  end;
  // Kurzschalter {$R-}, {$R-,Q+}, {$A4}; {$R Datei.res} oder {$I datei} ändern nichts.
  Changes := nil;
  Parts := ABody.Split([',']);
  for Part in Parts do
  begin
    Value := Trim(Part);
    if Length(Value) < 2 then
      Exit;
    Letter := UpCase(Value[1]);
    if Letter = 'A' then
    begin
      if AlignValue(Copy(Value, 2, MaxInt)) = '' then
        Exit;
      Changes := Changes + [TPair<string, string>.Create('A', AlignValue(Copy(Value, 2, MaxInt)))];
    end
    else if (Length(Value) = 2) and CharInSet(Value[2], ['+', '-']) then
      Changes := Changes + [TPair<string, string>.Create(Letter, Value[2])]
    else
      Exit;
  end;
  for Change in Changes do
    SetSwitch(AReplay, Change.Key, Change.Value, AOrigin);
end;

function SortedEntries(const AValues: TEnumerable<TSwitchEntry>): TSwitchEntries;
var
  Entry: TSwitchEntry;
  List: TList<TSwitchEntry>;
begin
  List := TList<TSwitchEntry>.Create;
  try
    for Entry in AValues do
      List.Add(Entry);
    // Namen sind eindeutig: die Sortierung ist eindeutig.
    List.Sort(TComparer<TSwitchEntry>.Construct(
      function(const ALeft, ARight: TSwitchEntry): Integer
      begin
        Result := CompareText(ALeft.Name, ARight.Name);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function OriginOf(const AProcessed: TPreprocessorResult; AFileIndex: Integer; const ARange: TTextRange;
  const AText: string): TSwitchOrigin;
begin
  if AFileIndex = 0 then
    Result := TSwitchOrigin.Make(TSwitchOriginKind.Directive, AText)
  else
    Result := TSwitchOrigin.Make(TSwitchOriginKind.Include, AText);
  if (AFileIndex >= 0) and (AFileIndex < Length(AProcessed.Files)) then
    Result.FileName := AProcessed.Files[AFileIndex];
  Result.Line := ARange.StartPos.Line;
end;

{ TCompilerSwitches }

class function TCompilerSwitches.At(const AProcessed: TPreprocessorResult; const APosition: TTextPosition;
  const AInput: TCompilerSwitchInput): TCompilerSwitchState;
var
  Project, Replay, Saved: TReplay;
  Stack: TObjectStack<TReplay>;
  Site: TDirectiveSite;
  DefineSite: TDefineSite;
  Name, Argument, Define: string;
  Index: Integer;
  Entry: TSwitchEntry;
  Origin: TSwitchDefineOrigin;
  Defines: TDictionary<string, TSwitchEntry>;
  Warn: TSwitchEntry;
begin
  Result := Default(TCompilerSwitchState);
  Project := TReplay.Create;
  Stack := TObjectStack<TReplay>.Create(True);
  Defines := TDictionary<string, TSwitchEntry>.Create;
  Replay := nil;
  try
    ProjectSwitches(AInput, Project);
    Replay := Project.Copy;
    for Site in AProcessed.DirectiveSites do
    begin
      if not Before(Site.RootPos, APosition) then
        Continue;
      Split(Site.Body, Name, Argument);
      if Name = 'PUSHOPT' then
        Stack.Push(Replay.Copy)
      else if Name = 'POPOPT' then
      begin
        if Stack.Count > 0 then
        begin
          Saved := Stack.Extract;
          Replay.Free;
          Replay := Saved;
        end;
      end
      else
        Apply(Replay, Project, Site.Body, OriginOf(AProcessed, Site.FileIndex, Site.Range, '{$' + Site.Body + '}'));
    end;
    for Index := 1 to Length(Letters) do
      Result.Switches := Result.Switches + [Replay.Switches[Letters[Index]]];
    Result.Hints := Replay.Switches['HINTS'];
    Result.Warnings := Replay.Switches['WARNINGS'];
    Result.Warns := nil;
    for Warn in SortedEntries(Replay.Warns.Values) do
      if Warn.Value <> 'ON' then
        Result.Warns := Result.Warns + [Warn];
    // Symbole: Projekt und Compiler, dann $DEFINE/$UNDEF vor der Stelle.
    for Define in AInput.Defines do
    begin
      if TPascalPreprocessor.IsSwitchEntry(Define) or (Trim(Define) = '') then
        Continue;
      Entry := Default(TSwitchEntry);
      Entry.Name := UpperCase(Trim(Define));
      Entry.Origin := TSwitchOrigin.Make(TSwitchOriginKind.Project, '');
      for Origin in AInput.DefineOrigins do
        if SameText(Origin.Name, Entry.Name) then
          Entry.Origin := Origin.Origin;
      Defines.AddOrSetValue(Entry.Name, Entry);
    end;
    for DefineSite in AProcessed.DefineSites do
    begin
      if not Before(DefineSite.RootPos, APosition) then
        Continue;
      if DefineSite.Undefine then
        Defines.Remove(DefineSite.Name)
      else
      begin
        Entry := Default(TSwitchEntry);
        Entry.Name := DefineSite.Name;
        Entry.Origin := OriginOf(AProcessed, DefineSite.FileIndex, DefineSite.Range,
          '{$DEFINE ' + DefineSite.Name + '}');
        Defines.AddOrSetValue(Entry.Name, Entry);
      end;
    end;
    Result.Defines := SortedEntries(Defines.Values);
  finally
    Replay.Free;
    Defines.Free;
    Stack.Free;
    Project.Free;
  end;
end;

{ TCompilerSwitchState }

function TCompilerSwitchState.Summary: string;
var
  Entry: TSwitchEntry;
  Parts: TArray<string>;
  Count: Integer;
begin
  Parts := nil;
  for Entry in Switches do
    if Entry.Deviates then
    begin
      if Entry.Name = 'A' then
        Parts := Parts + ['A' + Entry.Value]
      else if Entry.Value = '-' then
        Parts := Parts + [Entry.Name + MinusSign]
      else
        Parts := Parts + [Entry.Name + Entry.Value];
    end;
  if Hints.Deviates then
    Parts := Parts + ['HINTS ' + Hints.Value];
  if Warnings.Deviates then
    Parts := Parts + ['WARNINGS ' + Warnings.Value];
  Count := 0;
  for Entry in Warns do
    if Entry.Deviates then
      Inc(Count);
  if Count = 1 then
  begin
    for Entry in Warns do
      if Entry.Deviates then
        Parts := Parts + ['WARN ' + Entry.Name + ' ' + Entry.Value];
  end
  else if Count > 1 then
    Parts := Parts + [Format('WARN %d×', [Count])];
  Result := String.Join(' ', Parts);
end;

end.
