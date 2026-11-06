unit Atlas.Core.Forms.Changes;

// Änderungen des Servers an einem offenen Formular (#402), Teil ohne VCL und
// Open Tools API. Die Datei auf der Platte zu ändern hilft nicht: Der
// Designer überschreibt sie beim nächsten Speichern. Atlas wendet die
// Änderungen deshalb auf den zuletzt gesendeten Formulartext an und
// vergleicht Zeile für Zeile. Unterstützt sind geänderte Ereignis-Zuordnungen
// („OnClick = Alt“ → „OnClick = Neu“, etwa nach dem Umbenennen eines
// Handlers) und, mit der zweiten Überladung von Diff, einzeilige Eigenschaften
// (#309: Eigenschaftsregeln): geänderter Wert, neue Zeile oder entfernte Zeile
// (zurück zum Vorgabewert). Die IDE-Schicht setzt beides über den Designer.
// Alles andere (neue oder umbenannte Komponenten, mehrzeilige Werte, Einträge
// in Kollektionen) meldet Diff als nicht unterstützt, und Atlas ändert dann
// nichts.

interface

uses
  System.SysUtils;

type
  TAtlasFormEventChange = record
    /// <summary>Name der Komponente; '' = das Formular selbst.</summary>
    Component: string;
    /// <summary>Ereignis-Eigenschaft, z. B. OnClick.</summary>
    EventName: string;
    OldHandler: string;
    NewHandler: string;
  end;

  /// <summary>Geänderte Eigenschaft eines offenen Formulars (#309).</summary>
  TAtlasFormPropertyChange = record
    /// <summary>Name der Komponente; '' = das Formular selbst.</summary>
    Component: string;
    /// <summary>Pfad wie in der Datei, auch Font.Name.</summary>
    PropertyPath: string;
    /// <summary>Neuer Wert als DFM-Text, z. B. True, 'Segoe UI' oder [a, b]; leer bei Removed.</summary>
    Value: string;
    /// <summary>Zeile entfernt: zurück zum Vorgabewert der Eigenschaft.</summary>
    Removed: Boolean;
    /// <summary>1-basierte Zeile im alten Text bzw. vor der eingefügten Zeile, für Meldungen.</summary>
    Line: Integer;
  end;

  TAtlasFormChanges = class
  public
    /// <summary>Vergleicht zwei Formulartexte. True, wenn sie sich höchstens in Ereignis-Zuordnungen
    /// unterscheiden (AChanges ist dann die Liste); False mit AReason sonst.</summary>
    class function Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
      out AReason: string): Boolean; overload; static;
    /// <summary>Wie oben, erlaubt zusätzlich einzeilige Eigenschaften (AProperties, #309).</summary>
    class function Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
      out AProperties: TArray<TAtlasFormPropertyChange>; out AReason: string): Boolean; overload; static;
    /// <summary>Name aus einer Zeile "object Name: TTyp" (auch inherited, inline); '' sonst.</summary>
    class function ObjectName(const ALine: string; out AIsObject: Boolean): string; static;
    /// <summary>String-Wert der DFM ('Segoe UI', 'a'#13'b', mit + verkettet) als Text; False bei anderem.</summary>
    class function StringValue(const AValue: string; out AText: string): Boolean; static;
  end;

implementation

uses
  Atlas.Text.Lines;

function IsIdentifier(const AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := AValue <> '';
  for Index := 1 to Length(AValue) do
  begin
    if not (CharInSet(AValue[Index], ['A'..'Z', 'a'..'z', '_']) or
      ((Index > 1) and CharInSet(AValue[Index], ['0'..'9']))) then
    begin
      Exit(False);
    end;
  end;
end;

function IsPath(const AValue: string): Boolean;
var
  Part: string;
begin
  Result := AValue <> '';
  for Part in AValue.Split(['.']) do
  begin
    if not IsIdentifier(Part) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>"Name = Wert" mit vollständigem, einzeiligem Wert; False sonst.</summary>
function PropertyLine(const ALine: string; out AName, AValue: string): Boolean;
var
  Separator: Integer;
begin
  Separator := Pos(' = ', ALine);
  Result := Separator > 0;
  if not Result then
  begin
    Exit;
  end;
  AName := Trim(Copy(ALine, 1, Separator - 1));
  AValue := Trim(Copy(ALine, Separator + 3, MaxInt));
  // Mehrzeilige Werte beginnen mit (, < oder { bzw. enden mit +.
  Result := IsPath(AName) and (AValue <> '') and not CharInSet(AValue[1], ['(', '<', '{']) and
    not AValue.EndsWith('+');
end;

/// <summary>Gleiche Zeile oder dieselbe Eigenschaft mit anderem Wert: passt für die Suche nach eingefügten und
/// entfernten Zeilen.</summary>
function SameKey(const A, B: string): Boolean;
var
  NameA, ValueA, NameB, ValueB: string;
begin
  Result := (A = B) or (PropertyLine(A, NameA, ValueA) and PropertyLine(B, NameB, ValueB) and (NameA = NameB));
end;

function IsEventName(const AName: string): Boolean;
begin
  Result := (Length(AName) > 2) and AName.StartsWith('On') and CharInSet(AName[3], ['A'..'Z']) and
    IsIdentifier(AName);
end;

type
  /// <summary>Zustand von Diff: beide Zeilenlisten, Stapel der offenen Objekte und das Ergebnis.</summary>
  TFormDiff = record
    OldLines: TArray<string>;
    NewLines: TArray<string>;
    Stack: TArray<string>;
    OldIndex: Integer;
    NewIndex: Integer;
    Changes: TArray<TAtlasFormEventChange>;
    Properties: TArray<TAtlasFormPropertyChange>;
    Reason: string;
    procedure Track(const ALine: string);
    /// <summary>Innerhalb eines Objekts, nicht in einem Kollektionseintrag.</summary>
    function InObject: Boolean;
    function Component: string;
    function Fail(ALine: Integer; const AText: string): Boolean;
    function NewProperty(const AName, AValue: string; ARemoved: Boolean; ALine: Integer): TAtlasFormPropertyChange;
    function BothLeft: Boolean;
    function SameLine: Boolean;
    /// <summary>Gleiche Eigenschaft, anderer Wert; AOk False, wenn die Änderung nicht geht.</summary>
    function ChangedLine(out AOk: Boolean): Boolean;
    function TakeChange(const AName, AOldValue, ANewValue: string): Boolean;
    /// <summary>Eingefügte Eigenschaft: danach geht es mit der alten Zeile weiter.</summary>
    function InsertedLine: Boolean;
    /// <summary>Entfernte Eigenschaft: zurück zum Vorgabewert.</summary>
    function RemovedLine: Boolean;
    function Step: Boolean;
    function Run: Boolean;
  end;

procedure TFormDiff.Track(const ALine: string);
var
  mName, mTrimmed: string;
  mIsObject: Boolean;
begin
  mName := TAtlasFormChanges.ObjectName(ALine, mIsObject);
  mTrimmed := Trim(ALine);
  if mIsObject then
  begin
    Stack := Stack + [mName];
  end
  else if SameText(mTrimmed, 'item') then
  begin
    Stack := Stack + [''];
  end
  // Das letzte Element einer Kollektion endet mit "end>".
  else if (SameText(mTrimmed, 'end') or SameText(mTrimmed, 'end>')) and (Length(Stack) > 0) then
  begin
    SetLength(Stack, Length(Stack) - 1);
  end;
end;

function TFormDiff.InObject: Boolean;
begin
  Result := (Length(Stack) > 0) and ((Length(Stack) = 1) or (Stack[High(Stack)] <> ''));
end;

function TFormDiff.Component: string;
begin
  // Die oberste Ebene ist das Formular selbst.
  Result := '';
  if Length(Stack) > 1 then
  begin
    Result := Stack[High(Stack)];
  end;
end;

function TFormDiff.Fail(ALine: Integer; const AText: string): Boolean;
begin
  Changes := nil;
  Properties := nil;
  Reason := Format('Zeile %d: %s', [ALine, Trim(AText)]);
  Result := False;
end;

function TFormDiff.NewProperty(const AName, AValue: string; ARemoved: Boolean;
  ALine: Integer): TAtlasFormPropertyChange;
begin
  Result.Component := Component;
  Result.PropertyPath := AName;
  Result.Value := AValue;
  Result.Removed := ARemoved;
  Result.Line := ALine;
end;

function TFormDiff.BothLeft: Boolean;
begin
  Result := (OldIndex <= High(OldLines)) and (NewIndex <= High(NewLines));
end;

function TFormDiff.SameLine: Boolean;
begin
  Result := BothLeft and (OldLines[OldIndex] = NewLines[NewIndex]);
  if Result then
  begin
    Track(OldLines[OldIndex]);
    Inc(OldIndex);
    Inc(NewIndex);
  end;
end;

function TFormDiff.TakeChange(const AName, AOldValue, ANewValue: string): Boolean;
var
  mChange: TAtlasFormEventChange;
begin
  Result := InObject;
  if not Result then
  begin
    Exit;
  end;
  if IsEventName(AName) then
  begin
    Result := IsIdentifier(AOldValue) and IsIdentifier(ANewValue);
    mChange.Component := Component;
    mChange.EventName := AName;
    mChange.OldHandler := AOldValue;
    mChange.NewHandler := ANewValue;
    Changes := Changes + [mChange];
  end
  else
  begin
    Properties := Properties + [NewProperty(AName, ANewValue, False, OldIndex + 1)];
  end;
end;

function TFormDiff.ChangedLine(out AOk: Boolean): Boolean;
var
  mOldName, mOldValue, mNewName, mNewValue: string;
begin
  AOk := True;
  Result := BothLeft and PropertyLine(OldLines[OldIndex], mOldName, mOldValue) and
    PropertyLine(NewLines[NewIndex], mNewName, mNewValue) and (mOldName = mNewName);
  if not Result then
  begin
    Exit;
  end;
  AOk := TakeChange(mOldName, mOldValue, mNewValue);
  if AOk then
  begin
    Inc(OldIndex);
    Inc(NewIndex);
  end
  else
  begin
    Fail(OldIndex + 1, OldLines[OldIndex]);
  end;
end;

function TFormDiff.InsertedLine: Boolean;
var
  mName, mValue: string;
begin
  Result := (NewIndex < High(NewLines)) and (OldIndex <= High(OldLines)) and
    SameKey(NewLines[NewIndex + 1], OldLines[OldIndex]) and PropertyLine(NewLines[NewIndex], mName, mValue);
  Result := Result and not IsEventName(mName) and InObject;
  if Result then
  begin
    Properties := Properties + [NewProperty(mName, mValue, False, OldIndex + 1)];
    Inc(NewIndex);
  end;
end;

function TFormDiff.RemovedLine: Boolean;
var
  mName, mValue: string;
begin
  Result := (OldIndex < High(OldLines)) and (NewIndex <= High(NewLines)) and
    SameKey(OldLines[OldIndex + 1], NewLines[NewIndex]) and PropertyLine(OldLines[OldIndex], mName, mValue);
  Result := Result and not IsEventName(mName) and InObject;
  if Result then
  begin
    Properties := Properties + [NewProperty(mName, '', True, OldIndex + 1)];
    Inc(OldIndex);
  end;
end;

function TFormDiff.Step: Boolean;
begin
  Result := True;
  if not (SameLine or ChangedLine(Result) or InsertedLine or RemovedLine) then
  begin
    if OldIndex <= High(OldLines) then
    begin
      Result := Fail(OldIndex + 1, OldLines[OldIndex]);
    end
    else
    begin
      Result := Fail(OldIndex + 1, NewLines[NewIndex]);
    end;
  end;
end;

function TFormDiff.Run: Boolean;
begin
  Result := True;
  while Result and ((OldIndex <= High(OldLines)) or (NewIndex <= High(NewLines))) do
  begin
    Result := Step;
  end;
end;

class function TAtlasFormChanges.ObjectName(const ALine: string; out AIsObject: Boolean): string;
var
  Line, Keyword: string;
  Colon: Integer;
begin
  Result := '';
  Line := Trim(ALine);
  AIsObject := False;
  for Keyword in TArray<string>.Create('object ', 'inherited ', 'inline ') do
  begin
    if Line.StartsWith(Keyword, True) then
    begin
      AIsObject := True;
      Line := Trim(Copy(Line, Length(Keyword) + 1, MaxInt));
      Colon := Pos(':', Line);
      // Ohne Doppelpunkt ("object TTimer") hat die Komponente keinen Namen.
      if Colon > 0 then
      begin
        Result := Trim(Copy(Line, 1, Colon - 1));
      end;
      Exit;
    end;
  end;
end;

/// <summary>'…' ab AIndex (auf dem Anführungszeichen) an AText hängen; '' steht für eines.</summary>
procedure TakeQuoted(const AValue: string; var AIndex: Integer; var AText: string);
begin
  Inc(AIndex);
  while AIndex <= Length(AValue) do
  begin
    if AValue[AIndex] <> '''' then
    begin
      AText := AText + AValue[AIndex];
      Inc(AIndex);
    end
    else if (AIndex < Length(AValue)) and (AValue[AIndex + 1] = '''') then
    begin
      AText := AText + '''';
      Inc(AIndex, 2);
    end
    else
    begin
      Inc(AIndex);
      Break;
    end;
  end;
end;

/// <summary>#Zahl ab AIndex (auf dem #) an AText hängen; False ohne Zahl.</summary>
function TakeCharCode(const AValue: string; var AIndex: Integer; var AText: string): Boolean;
var
  Start, Code: Integer;
begin
  Inc(AIndex);
  Start := AIndex;
  while (AIndex <= Length(AValue)) and CharInSet(AValue[AIndex], ['0'..'9']) do
  begin
    Inc(AIndex);
  end;
  Result := TryStrToInt(Copy(AValue, Start, AIndex - Start), Code);
  if Result then
  begin
    AText := AText + Char(Code);
  end;
end;

class function TAtlasFormChanges.StringValue(const AValue: string; out AText: string): Boolean;
var
  Index: Integer;
  Value: string;
begin
  AText := '';
  Value := Trim(AValue);
  Result := (Value <> '') and CharInSet(Value[1], ['''', '#']);
  Index := 1;
  while Result and (Index <= Length(Value)) do
    case Value[Index] of
      '''':
        TakeQuoted(Value, Index, AText);
      '#':
        Result := TakeCharCode(Value, Index, AText);
      ' ', '+', #13, #10, #9:
        Inc(Index);
    else
      Result := False;
    end;
  if not Result then
  begin
    AText := '';
  end;
end;

class function TAtlasFormChanges.Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
  out AReason: string): Boolean;
var
  Properties: TArray<TAtlasFormPropertyChange>;
begin
  Result := Diff(AOld, ANew, AChanges, Properties, AReason);
  if Result and (Length(Properties) > 0) then
  begin
    AChanges := nil;
    AReason := Format('Zeile %d: %s', [Properties[0].Line, Properties[0].PropertyPath]);
    Result := False;
  end;
end;

class function TAtlasFormChanges.Diff(const AOld, ANew: string; out AChanges: TArray<TAtlasFormEventChange>;
  out AProperties: TArray<TAtlasFormPropertyChange>; out AReason: string): Boolean;
var
  mDiff: TFormDiff;
begin
  mDiff := Default(TFormDiff);
  mDiff.OldLines := TTextLines.SplitLines(AOld);
  mDiff.NewLines := TTextLines.SplitLines(ANew);
  Result := mDiff.Run;
  AChanges := mDiff.Changes;
  AProperties := mDiff.Properties;
  AReason := mDiff.Reason;
end;

end.
