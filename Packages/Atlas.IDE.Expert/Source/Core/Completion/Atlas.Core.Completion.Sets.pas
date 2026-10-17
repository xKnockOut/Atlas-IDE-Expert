unit Atlas.Core.Completion.Sets;

// Mengenmodus der Vervollständigung (#448), ohne Fenster: In einem Mengenkonstruktor
// ("Anchors := [akLeft, ") liefert der Server alle Werte des Elementtyps mit SetOf,
// Checked (steht schon in der Klammer) und SetRange (von "[" bis hinter "]"). Die
// Liste zeigt Kontrollkästchen, die Leertaste schaltet um, Enter schreibt die ganze
// Klammer neu: angehakte Werte in Deklarationsreihenfolge, bei {$SCOPEDENUMS ON} mit
// Typpräfix (InsertText). Esc verwirft.
//
// Interface implementieren (#466) nutzt dieselbe Liste: Batch-Einträge sind fehlende Methoden, alle angehakt.
// Enter entfernt das getippte Wort (SetRange) und übernimmt die AdditionalEdits der angehakten Einträge in
// Ordinal-Reihenfolge. Einfügungen an derselben Stelle (Abschnitt, Kommentar je Interface, Deklarationen bzw.
// Rümpfe) werden zu einer zusammengefasst, gleiche Texte nur einmal.
//
// Alle Felder zuweisen (#491) mit mehr als 15 Feldern: Übernehmen des Eintrags macht aus seinen Assignments
// dieselbe Liste (AssignItems), alle angehakt; Enter entfernt den Ausdruck und setzt die angehakten Zeilen ein.

interface

uses
  Atlas.Core.Completion.Contract;

type
  TAtlasCompletionSets = class
  public
    /// <summary>Die Liste ist im Mengenmodus.</summary>
    class function Active(const AItems: TAtlasCompletionItems): Boolean; static;
    class function CheckedCount(const AItems: TAtlasCompletionItems): Integer; static;
    /// <summary>Neuer Klammerinhalt, z. B. "[akLeft, akTop]"; "[]" ohne angehakte Werte.</summary>
    class function Text(const AItems: TAtlasCompletionItems): string; static;
    /// <summary>Eintrag, der beim Übernehmen die Klammer durch Text ersetzt (textEdit über SetRange).</summary>
    class function CommitItem(const AItems: TAtlasCompletionItems): TAtlasCompletionItem; static;
    /// <summary>Fasst Änderungen mit gleichem Bereich zusammen (#466): Texte in der Reihenfolge des ersten
    /// Auftretens, gleiche nur einmal.</summary>
    class function Merge(const AEdits: TArray<TAtlasTextEdit>): TArray<TAtlasTextEdit>; static;
    /// <summary>Liste für „Alle Felder zuweisen“ (#491): je Zeile aus AItem.Assignments ein angehakter Eintrag
    /// (Batch, Assign); SetRange ist der textEdit von AItem (der Ausdruck mit Punkt), jede Zeile kommt an dessen
    /// Ende. Leer ohne Assignments.</summary>
    class function AssignItems(const AItem: TAtlasCompletionItem): TAtlasCompletionItems; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Angehakte Einträge nach Ordinal (wenige Einträge, Einfügen genügt).</summary>
function CheckedInOrder(const AItems: TAtlasCompletionItems): TAtlasCompletionItems;
var
  Item, Moved: TAtlasCompletionItem;
  Index, Scan: Integer;
begin
  Result := nil;
  for Item in AItems do
    if (Item.SetOf <> '') and Item.Checked then
      Result := Result + [Item];
  for Index := 1 to High(Result) do
  begin
    Moved := Result[Index];
    Scan := Index - 1;
    while (Scan >= 0) and (Result[Scan].Ordinal > Moved.Ordinal) do
    begin
      Result[Scan + 1] := Result[Scan];
      Dec(Scan);
    end;
    Result[Scan + 1] := Moved;
  end;
end;

function SameRange(const A, B: TAtlasTextEdit): Boolean;
begin
  Result := (A.StartLine = B.StartLine) and (A.StartCharacter = B.StartCharacter) and (A.EndLine = B.EndLine) and
    (A.EndCharacter = B.EndCharacter);
end;

class function TAtlasCompletionSets.Active(const AItems: TAtlasCompletionItems): Boolean;
var
  Item: TAtlasCompletionItem;
begin
  for Item in AItems do
    if Item.SetOf <> '' then
      Exit(True);
  Result := False;
end;

class function TAtlasCompletionSets.CheckedCount(const AItems: TAtlasCompletionItems): Integer;
var
  Item: TAtlasCompletionItem;
begin
  Result := 0;
  for Item in AItems do
    if (Item.SetOf <> '') and Item.Checked then
      Inc(Result);
end;

class function TAtlasCompletionSets.Text(const AItems: TAtlasCompletionItems): string;
var
  Chosen: TAtlasCompletionItems;
  Index: Integer;
begin
  Chosen := CheckedInOrder(AItems);
  Result := '';
  for Index := 0 to High(Chosen) do
  begin
    if Index > 0 then
      Result := Result + ', ';
    if Chosen[Index].InsertText <> '' then
      Result := Result + Chosen[Index].InsertText
    else
      Result := Result + Chosen[Index].Name;
  end;
  Result := '[' + Result + ']';
end;

class function TAtlasCompletionSets.Merge(const AEdits: TArray<TAtlasTextEdit>): TArray<TAtlasTextEdit>;
var
  Edit: TAtlasTextEdit;
  Index, Found: Integer;
  // Je Bereich die schon übernommenen Texte, mit #0 umschlossen.
  Seen: TArray<string>;
begin
  Result := nil;
  Seen := nil;
  for Edit in AEdits do
  begin
    Found := -1;
    for Index := 0 to High(Result) do
      if SameRange(Result[Index], Edit) then
      begin
        Found := Index;
        Break;
      end;
    if Found < 0 then
    begin
      Result := Result + [Edit];
      Seen := Seen + [#0 + Edit.NewText + #0];
    end
    else if Pos(#0 + Edit.NewText + #0, Seen[Found]) = 0 then
    begin
      Seen[Found] := Seen[Found] + Edit.NewText + #0;
      Result[Found].NewText := Result[Found].NewText + Edit.NewText;
    end;
  end;
end;

class function TAtlasCompletionSets.AssignItems(const AItem: TAtlasCompletionItem): TAtlasCompletionItems;
var
  Index: Integer;
  Range, Insert: TAtlasTextEdit;
  Title: string;
begin
  Result := nil;
  if not AItem.HasTextEdit then
    Exit;
  Range := AItem.TextEdit;
  Range.NewText := '';
  Insert := Range;
  Insert.StartLine := Range.EndLine;
  Insert.StartCharacter := Range.EndCharacter;
  // Überschrift mit dem Typ des Ausdrucks.
  Title := AItem.Signature;
  if Title = '' then
    Title := AItem.Name;
  SetLength(Result, Length(AItem.Assignments));
  for Index := 0 to High(AItem.Assignments) do
  begin
    Result[Index] := Default(TAtlasCompletionItem);
    Result[Index].Name := AItem.Assignments[Index].Name;
    Result[Index].Signature := AItem.Assignments[Index].Detail;
    Result[Index].Kind := TAtlasItemKind.Field;
    Result[Index].Batch := True;
    Result[Index].Assign := True;
    Result[Index].Ordinal := Index + 1;
    Result[Index].Checked := True;
    Result[Index].SetOf := Title;
    Result[Index].ExpectedType := Title;
    Result[Index].Fits := True;
    // Die Zusatzänderung ist kein uses-Eintrag.
    Result[Index].UnitUsed := True;
    Result[Index].SetRange := Range;
    Insert.NewText := AItem.Assignments[Index].Text;
    Result[Index].AdditionalEdits := [Insert];
  end;
end;

class function TAtlasCompletionSets.CommitItem(const AItems: TAtlasCompletionItems): TAtlasCompletionItem;
var
  Item, Chosen: TAtlasCompletionItem;
  Edits: TArray<TAtlasTextEdit>;
begin
  Result := Default(TAtlasCompletionItem);
  // Interface implementieren (#466): das getippte Wort weg, die Änderungen der angehakten Methoden dazu.
  for Item in AItems do
    if Item.Batch then
    begin
      Result.Name := Item.SetOf;
      Result.Kind := TAtlasItemKind.Method;
      // Erzeugt Code: die Zusatzänderungen gelten auch ohne automatische uses-Einträge.
      Result.IsAction := True;
      Result.HasTextEdit := True;
      Result.TextEdit := Item.SetRange;
      Result.TextEdit.NewText := '';
      Edits := nil;
      for Chosen in CheckedInOrder(AItems) do
        Edits := Edits + Chosen.AdditionalEdits;
      Result.AdditionalEdits := Merge(Edits);
      Exit;
    end;
  Result.Name := Text(AItems);
  Result.Kind := TAtlasItemKind.EnumMember;
  Result.InsertText := Result.Name;
  for Item in AItems do
    if Item.SetOf <> '' then
    begin
      Result.HasTextEdit := True;
      Result.TextEdit := Item.SetRange;
      Result.TextEdit.NewText := Result.Name;
      Break;
    end;
end;

end.
