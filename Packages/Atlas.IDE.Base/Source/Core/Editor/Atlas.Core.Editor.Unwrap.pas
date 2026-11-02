unit Atlas.Core.Editor.Unwrap;

// Umschließung entfernen (#657), Kern im Plugin ohne VCL und ToolsAPI:
// Argumente für atlas.server.unwrap, die Antwort als Einträge der Liste (je
// Konstrukt und Variante einer, das innerste Konstrukt zuerst), die Stücke
// einer Zeile für die Vorschau (bleibt grün, entfällt rot) und das
// WorkspaceEdit des gewählten Eintrags. Ein Konstrukt ohne Variante (with
// nicht auflösbar) bleibt als Eintrag mit Hinweis stehen, lässt sich aber
// nicht übernehmen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.WorkspaceEdits;

type
  TAtlasUnwrapEntry = record
    /// <summary>Konstrukt: beginEnd, tryFinally, tryExcept, ifThen, withDo, forDo, whileDo, repeatUntil, ifdef,
    /// region.</summary>
    Kind: string;
    /// <summary>Variante: body, keepFinally, dropFinally, then, else, branch; '' ohne Variante.</summary>
    VariantKind: string;
    /// <summary>Nummer des Zweigs ab 0 bei Direktiven.</summary>
    Branch: Integer;
    /// <summary>Zahl der Varianten des Konstrukts.</summary>
    VariantCount: Integer;
    /// <summary>Hinweis: multipleRaise, loopVariable, withUnresolved oder ''.</summary>
    Note: string;
    NoteText: string;
    /// <summary>Erste Zeile des Konstrukts ab 0.</summary>
    Line: Integer;
    Edits: TArray<TLspTextEdit>;
    Keep: TArray<TLspRange>;
    Remove: TArray<TLspRange>;
    /// <summary>Lässt sich übernehmen (hat Edits)?</summary>
    function Available: Boolean;
  end;

  /// <summary>Stück einer Zeile in der Vorschau, Zeichen ab 0, Ende ausschließlich.</summary>
  TAtlasUnwrapSpan = record
    Start: Integer;
    Stop: Integer;
    Keep: Boolean;
  end;

  TAtlasUnwrap = class
  public const
    Command = 'atlas.server.unwrap';
    /// <summary>Strg+Umschalt+Entf.</summary>
    DefaultKey = $602E;
  public
    /// <summary>[uri, position, Einrückungsbreite]; AIndentWidth &lt;= 0 = Formatierstil des Servers.</summary>
    class function Arguments(const AUri: string; ALine, ACharacter, AIndentWidth: Integer): string; static;
    /// <summary>Einträge aus der Antwort; nil bei leerer oder fremder Antwort.</summary>
    class function ReadEntries(const AAnswer: TJSONValue): TArray<TAtlasUnwrapEntry>; static;
    /// <summary>Genau ein Konstrukt mit einer Variante: Die Liste entfällt, die Vorschau erscheint direkt.</summary>
    class function SingleEntry(const AEntries: TArray<TAtlasUnwrapEntry>): Boolean; static;
    /// <summary>Erster übernehmbarer Eintrag ab AFrom in Richtung ADelta (ringsum); -1 ohne.</summary>
    class function NextAvailable(const AEntries: TArray<TAtlasUnwrapEntry>; AFrom, ADelta: Integer): Integer; static;
    /// <summary>Stücke der Vorschau in Zeile ALine (ab 0), nach Anfang sortiert.</summary>
    class function SpansOnLine(const AEntry: TAtlasUnwrapEntry; ALine: Integer): TArray<TAtlasUnwrapSpan>; static;
    /// <summary>Erste und letzte Zeile der Vorschau; False ohne Bereiche.</summary>
    class function LineSpan(const AEntry: TAtlasUnwrapEntry; out AFirst, ALast: Integer): Boolean; static;
    /// <summary>Die Edits des Eintrags als Änderung an AFileName.</summary>
    class function EditOf(const AEntry: TAtlasUnwrapEntry; const AFileName: string): TLspWorkspaceEdit; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

function ReadPosition(const AValue: TJSONValue; out APosition: TLspTextPosition): Boolean;
var
  Line, Character: Integer;
begin
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<Integer>('line', Line) and
    TJSONObject(AValue).TryGetValue<Integer>('character', Character);
  if Result then
    APosition := TLspTextPosition.Create(Line, Character);
end;

function ReadRange(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and ReadPosition(TJSONObject(AValue).GetValue('start'), ARange.StartPos) and
    ReadPosition(TJSONObject(AValue).GetValue('end'), ARange.EndPos);
end;

function ReadRanges(const AValue: TJSONValue): TArray<TLspRange>;
var
  Item: TJSONValue;
  Range: TLspRange;
begin
  Result := nil;
  if AValue is TJSONArray then
    for Item in TJSONArray(AValue) do
      if ReadRange(Item, Range) then
        Result := Result + [Range];
end;

function ReadEdits(const AValue: TJSONValue): TArray<TLspTextEdit>;
var
  Item: TJSONValue;
  Edit: TLspTextEdit;
begin
  Result := nil;
  if AValue is TJSONArray then
    for Item in TJSONArray(AValue) do
      if TLspTextEdit.FromJson(Item, Edit) then
        Result := Result + [Edit];
end;

function StringOf(const AObject: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AObject.GetValue(AName) is TJSONString then
    Result := AObject.GetValue(AName).Value;
end;

{ TAtlasUnwrapEntry }

function TAtlasUnwrapEntry.Available: Boolean;
begin
  Result := Length(Edits) > 0;
end;

{ TAtlasUnwrap }

class function TAtlasUnwrap.Arguments(const AUri: string; ALine, ACharacter, AIndentWidth: Integer): string;
var
  List: TJSONArray;
  Position: TJSONObject;
begin
  List := TJSONArray.Create;
  try
    List.Add(AUri);
    Position := TJSONObject.Create;
    Position.AddPair('line', TJSONNumber.Create(ALine));
    Position.AddPair('character', TJSONNumber.Create(ACharacter));
    List.AddElement(Position);
    List.Add(AIndentWidth);
    Result := List.ToJSON;
  finally
    List.Free;
  end;
end;

class function TAtlasUnwrap.ReadEntries(const AAnswer: TJSONValue): TArray<TAtlasUnwrapEntry>;
var
  Candidates, Variants: TJSONArray;
  Item, VariantItem: TJSONValue;
  Candidate, Choice: TJSONObject;
  Entry: TAtlasUnwrapEntry;
  Range: TLspRange;
  Branch: Integer;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) or not (TJSONObject(AAnswer).GetValue('candidates') is TJSONArray) then
    Exit;
  Candidates := TJSONArray(TJSONObject(AAnswer).GetValue('candidates'));
  for Item in Candidates do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Candidate := TJSONObject(Item);
    Entry := Default(TAtlasUnwrapEntry);
    Entry.Kind := StringOf(Candidate, 'kind');
    Entry.Note := StringOf(Candidate, 'note');
    Entry.NoteText := StringOf(Candidate, 'noteText');
    if ReadRange(Candidate.GetValue('range'), Range) then
      Entry.Line := Range.StartPos.Line;
    Variants := nil;
    if Candidate.GetValue('variants') is TJSONArray then
      Variants := TJSONArray(Candidate.GetValue('variants'));
    if (Variants = nil) or (Variants.Count = 0) then
    begin
      // Nicht übernehmbar, aber mit Hinweis in der Liste.
      Result := Result + [Entry];
      Continue;
    end;
    Entry.VariantCount := Variants.Count;
    for VariantItem in Variants do
    begin
      if not (VariantItem is TJSONObject) then
        Continue;
      Choice := TJSONObject(VariantItem);
      Entry.VariantKind := StringOf(Choice, 'kind');
      Entry.Branch := 0;
      if Choice.TryGetValue<Integer>('branch', Branch) then
        Entry.Branch := Branch;
      Entry.Edits := ReadEdits(Choice.GetValue('edits'));
      Entry.Keep := ReadRanges(Choice.GetValue('keep'));
      Entry.Remove := ReadRanges(Choice.GetValue('remove'));
      Result := Result + [Entry];
    end;
  end;
end;

class function TAtlasUnwrap.SingleEntry(const AEntries: TArray<TAtlasUnwrapEntry>): Boolean;
begin
  Result := (Length(AEntries) = 1) and AEntries[0].Available;
end;

class function TAtlasUnwrap.NextAvailable(const AEntries: TArray<TAtlasUnwrapEntry>; AFrom, ADelta: Integer): Integer;
var
  Count, Step, Index: Integer;
begin
  Result := -1;
  Count := Length(AEntries);
  if Count = 0 then
    Exit;
  if ADelta = 0 then
    ADelta := 1;
  for Step := 0 to Count - 1 do
  begin
    Index := ((AFrom + Step * ADelta) mod Count + Count) mod Count;
    if AEntries[Index].Available then
      Exit(Index);
  end;
end;

class function TAtlasUnwrap.SpansOnLine(const AEntry: TAtlasUnwrapEntry; ALine: Integer): TArray<TAtlasUnwrapSpan>;

  procedure AddFrom(const ARanges: TArray<TLspRange>; AKeep: Boolean; var ASpans: TArray<TAtlasUnwrapSpan>);
  var
    Range: TLspRange;
    Span: TAtlasUnwrapSpan;
  begin
    for Range in ARanges do
    begin
      if (Range.StartPos.Line > ALine) or (Range.EndPos.Line < ALine) then
        Continue;
      Span.Start := 0;
      if Range.StartPos.Line = ALine then
        Span.Start := Range.StartPos.Character;
      Span.Stop := MaxInt;
      if Range.EndPos.Line = ALine then
        Span.Stop := Range.EndPos.Character;
      Span.Keep := AKeep;
      if Span.Stop > Span.Start then
        ASpans := ASpans + [Span];
    end;
  end;

begin
  Result := nil;
  AddFrom(AEntry.Keep, True, Result);
  AddFrom(AEntry.Remove, False, Result);
  TArray.Sort<TAtlasUnwrapSpan>(Result, TComparer<TAtlasUnwrapSpan>.Construct(
    function(const A, B: TAtlasUnwrapSpan): Integer
    begin
      Result := A.Start - B.Start;
    end));
end;

class function TAtlasUnwrap.LineSpan(const AEntry: TAtlasUnwrapEntry; out AFirst, ALast: Integer): Boolean;
var
  Range: TLspRange;
begin
  AFirst := MaxInt;
  ALast := -1;
  for Range in AEntry.Keep + AEntry.Remove do
  begin
    if Range.StartPos.Line < AFirst then
      AFirst := Range.StartPos.Line;
    if Range.EndPos.Line > ALast then
      ALast := Range.EndPos.Line;
  end;
  Result := ALast >= 0;
  if not Result then
    AFirst := -1;
end;

class function TAtlasUnwrap.EditOf(const AEntry: TAtlasUnwrapEntry; const AFileName: string): TLspWorkspaceEdit;
var
  FileEdits: TLspFileEdits;
begin
  Result := TLspWorkspaceEdit.FromJson(nil);
  if not AEntry.Available then
    Exit;
  FileEdits.FileName := AFileName;
  FileEdits.Edits := AEntry.Edits;
  Result.Files := [FileEdits];
end;

end.
