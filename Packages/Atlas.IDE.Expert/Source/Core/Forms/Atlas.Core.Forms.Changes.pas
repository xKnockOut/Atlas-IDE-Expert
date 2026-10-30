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
    if not (CharInSet(AValue[Index], ['A'..'Z', 'a'..'z', '_']) or
      ((Index > 1) and CharInSet(AValue[Index], ['0'..'9']))) then
      Exit(False);
end;

function IsPath(const AValue: string): Boolean;
var
  Part: string;
begin
  Result := AValue <> '';
  for Part in AValue.Split(['.']) do
    if not IsIdentifier(Part) then
      Exit(False);
end;

/// <summary>"Name = Wert" mit vollständigem, einzeiligem Wert; False sonst.</summary>
function PropertyLine(const ALine: string; out AName, AValue: string): Boolean;
var
  Separator: Integer;
begin
  Separator := Pos(' = ', ALine);
  Result := Separator > 0;
  if not Result then
    Exit;
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

class function TAtlasFormChanges.ObjectName(const ALine: string; out AIsObject: Boolean): string;
var
  Line, Keyword: string;
  Colon: Integer;
begin
  Result := '';
  Line := Trim(ALine);
  AIsObject := False;
  for Keyword in TArray<string>.Create('object ', 'inherited ', 'inline ') do
    if Line.StartsWith(Keyword, True) then
    begin
      AIsObject := True;
      Line := Trim(Copy(Line, Length(Keyword) + 1, MaxInt));
      Colon := Pos(':', Line);
      // Ohne Doppelpunkt ("object TTimer") hat die Komponente keinen Namen.
      if Colon > 0 then
        Result := Trim(Copy(Line, 1, Colon - 1));
      Exit;
    end;
end;

class function TAtlasFormChanges.StringValue(const AValue: string; out AText: string): Boolean;
var
  Index, Start, Code: Integer;
  Value: string;
begin
  AText := '';
  Value := Trim(AValue);
  Result := (Value <> '') and CharInSet(Value[1], ['''', '#']);
  if not Result then
    Exit;
  Index := 1;
  while Index <= Length(Value) do
    case Value[Index] of
      '''':
        begin
          Inc(Index);
          while Index <= Length(Value) do
          begin
            if Value[Index] = '''' then
            begin
              if (Index < Length(Value)) and (Value[Index + 1] = '''') then
              begin
                AText := AText + '''';
                Inc(Index, 2);
                Continue;
              end;
              Inc(Index);
              Break;
            end;
            AText := AText + Value[Index];
            Inc(Index);
          end;
        end;
      '#':
        begin
          Inc(Index);
          Start := Index;
          while (Index <= Length(Value)) and CharInSet(Value[Index], ['0'..'9']) do
            Inc(Index);
          if not TryStrToInt(Copy(Value, Start, Index - Start), Code) then
            Exit(False);
          AText := AText + Char(Code);
        end;
      ' ', '+', #13, #10, #9:
        Inc(Index);
    else
      Exit(False);
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
  OldLines, NewLines, Stack: TArray<string>;
  OldIndex, NewIndex: Integer;
  OldName, OldValue, NewName, NewValue: string;
  Change: TAtlasFormEventChange;
  Prop: TAtlasFormPropertyChange;

  procedure Track(const ALine: string);
  var
    Name, Trimmed: string;
    IsObject: Boolean;
  begin
    Name := ObjectName(ALine, IsObject);
    Trimmed := Trim(ALine);
    if IsObject then
      Stack := Stack + [Name]
    else if SameText(Trimmed, 'item') then
      Stack := Stack + ['']
    // Das letzte Element einer Kollektion endet mit "end>".
    else if (SameText(Trimmed, 'end') or SameText(Trimmed, 'end>')) and (Length(Stack) > 0) then
      SetLength(Stack, Length(Stack) - 1);
  end;

  /// <summary>Innerhalb eines Objekts, nicht in einem Kollektionseintrag.</summary>
  function InObject: Boolean;
  begin
    Result := (Length(Stack) > 0) and ((Length(Stack) = 1) or (Stack[High(Stack)] <> ''));
  end;

  function Component: string;
  begin
    // Die oberste Ebene ist das Formular selbst.
    Result := '';
    if Length(Stack) > 1 then
      Result := Stack[High(Stack)];
  end;

  function Fail(ALine: Integer; const AText: string): Boolean;
  begin
    AChanges := nil;
    AProperties := nil;
    AReason := Format('Zeile %d: %s', [ALine, Trim(AText)]);
    Result := False;
  end;

  function NewProperty(const AName, AValue: string; ARemoved: Boolean; ALine: Integer): TAtlasFormPropertyChange;
  begin
    Result.Component := Component;
    Result.PropertyPath := AName;
    Result.Value := AValue;
    Result.Removed := ARemoved;
    Result.Line := ALine;
  end;

begin
  AChanges := nil;
  AProperties := nil;
  AReason := '';
  OldLines := TTextLines.SplitLines(AOld);
  NewLines := TTextLines.SplitLines(ANew);
  Stack := nil;
  OldIndex := 0;
  NewIndex := 0;
  while (OldIndex <= High(OldLines)) or (NewIndex <= High(NewLines)) do
  begin
    if (OldIndex <= High(OldLines)) and (NewIndex <= High(NewLines)) and
      (OldLines[OldIndex] = NewLines[NewIndex]) then
    begin
      Track(OldLines[OldIndex]);
      Inc(OldIndex);
      Inc(NewIndex);
      Continue;
    end;
    // Geänderte Zeile: gleiche Eigenschaft, anderer Wert.
    if (OldIndex <= High(OldLines)) and (NewIndex <= High(NewLines)) and
      PropertyLine(OldLines[OldIndex], OldName, OldValue) and PropertyLine(NewLines[NewIndex], NewName, NewValue) and
      (OldName = NewName) then
    begin
      if not InObject then
        Exit(Fail(OldIndex + 1, OldLines[OldIndex]));
      if IsEventName(OldName) then
      begin
        if not IsIdentifier(OldValue) or not IsIdentifier(NewValue) then
          Exit(Fail(OldIndex + 1, OldLines[OldIndex]));
        Change.Component := Component;
        Change.EventName := OldName;
        Change.OldHandler := OldValue;
        Change.NewHandler := NewValue;
        AChanges := AChanges + [Change];
      end
      else
        AProperties := AProperties + [NewProperty(NewName, NewValue, False, OldIndex + 1)];
      Inc(OldIndex);
      Inc(NewIndex);
      Continue;
    end;
    // Eingefügte Eigenschaft: danach geht es mit der alten Zeile weiter.
    if (NewIndex < High(NewLines)) and (OldIndex <= High(OldLines)) and
      SameKey(NewLines[NewIndex + 1], OldLines[OldIndex]) and PropertyLine(NewLines[NewIndex], NewName, NewValue) and
      not IsEventName(NewName) and InObject then
    begin
      AProperties := AProperties + [NewProperty(NewName, NewValue, False, OldIndex + 1)];
      Inc(NewIndex);
      Continue;
    end;
    // Entfernte Eigenschaft: zurück zum Vorgabewert.
    if (OldIndex < High(OldLines)) and (NewIndex <= High(NewLines)) and
      SameKey(OldLines[OldIndex + 1], NewLines[NewIndex]) and PropertyLine(OldLines[OldIndex], OldName, OldValue) and
      not IsEventName(OldName) and InObject then
    begin
      Prop := NewProperty(OldName, '', True, OldIndex + 1);
      AProperties := AProperties + [Prop];
      Inc(OldIndex);
      Continue;
    end;
    if OldIndex <= High(OldLines) then
      Exit(Fail(OldIndex + 1, OldLines[OldIndex]));
    Exit(Fail(OldIndex + 1, NewLines[NewIndex]));
  end;
  Result := True;
end;

end.
