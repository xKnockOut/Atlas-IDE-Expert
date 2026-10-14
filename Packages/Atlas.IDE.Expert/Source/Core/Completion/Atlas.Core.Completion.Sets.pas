unit Atlas.Core.Completion.Sets;

// Mengenmodus der Vervollständigung (#448), ohne Fenster: In einem Mengenkonstruktor
// ("Anchors := [akLeft, ") liefert der Server alle Werte des Elementtyps mit SetOf,
// Checked (steht schon in der Klammer) und SetRange (von "[" bis hinter "]"). Die
// Liste zeigt Kontrollkästchen, die Leertaste schaltet um, Enter schreibt die ganze
// Klammer neu: angehakte Werte in Deklarationsreihenfolge, bei {$SCOPEDENUMS ON} mit
// Typpräfix (InsertText). Esc verwirft.

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
  end;

implementation

uses
  System.SysUtils;

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
  Item, Moved: TAtlasCompletionItem;
  Index, Scan: Integer;
begin
  Chosen := nil;
  for Item in AItems do
    if (Item.SetOf <> '') and Item.Checked then
      Chosen := Chosen + [Item];
  // Nach Ordinal sortieren (wenige Einträge, Einfügen genügt).
  for Index := 1 to High(Chosen) do
  begin
    Moved := Chosen[Index];
    Scan := Index - 1;
    while (Scan >= 0) and (Chosen[Scan].Ordinal > Moved.Ordinal) do
    begin
      Chosen[Scan + 1] := Chosen[Scan];
      Dec(Scan);
    end;
    Chosen[Scan + 1] := Moved;
  end;
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

class function TAtlasCompletionSets.CommitItem(const AItems: TAtlasCompletionItems): TAtlasCompletionItem;
var
  Item: TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
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
