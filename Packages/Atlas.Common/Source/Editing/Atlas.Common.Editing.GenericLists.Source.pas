unit Atlas.Common.Editing.GenericLists.Source;

// Eine Datei der Listenumwandlung (#1105, #1106): Syntaxbaum, Text und die gesammelten Edits. Merkt sich, wo der
// generische Typ neu im Text steht (für das uses) und welche alten Klassennamen umgeschrieben werden (ob Contnrs
// danach noch gebraucht wird). Finalize setzt die Platzhalter ein, sortiert und schließt Überschneidungen aus.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree;

const
  // Platzhalter in Edits, bis der Elementtyp feststeht: generischer Typ bzw. Elementtyp.
  cGenericPlaceholder = #1'G';
  cItemPlaceholder = #1'T';

type
  /// <summary>Bereich im Text als Offsets.</summary>
  TGenericListRange = record
    StartOffset: Integer;
    EndOffset: Integer;
    /// <summary>AOffset liegt im Bereich (Ende ausgeschlossen).</summary>
    function Contains(AOffset: Integer): Boolean;
  end;

  /// <summary>Eine Datei der Umwandlung mit ihren Edits.</summary>
  TGenericListSource = class
  private
    FTree: TSyntaxTree;
    FOwnsTree: Boolean;
    FText: string;
    FFileName: string;
    FLineBreak: string;
    FEdits: TArray<TTextEdit>;
    FGenericAt: TArray<Integer>;
    FRewritten: TArray<TGenericListRange>;
    function IsRewritten(AOffset: Integer): Boolean;
    function ContnrsTypeKept(AIndex: Integer): Boolean;
    function SortedEdits(const AGenericText, AItemType: string): TArray<TTextEdit>;
    class function EditBefore(const AFirst, ASecond: TTextEdit): Boolean; static;
    class function SameEdit(const AFirst, ASecond: TTextEdit): Boolean; static;
  public
    /// <summary>ATree gehört der Datei, wenn AOwnsTree.</summary>
    constructor Create(ATree: TSyntaxTree; AOwnsTree: Boolean; const AText, AFileName: string);
    destructor Destroy; override;
    /// <summary>Quelltext von ANode.</summary>
    function NodeText(ANode: TSyntaxNode): string;
    procedure AddEdit(const AStart, AEnd: TTextPosition; const ANewText: string);
    procedure AddTextEdit(const AEdit: TTextEdit);
    /// <summary>Der alte Klassenname an ANode wird umgeschrieben; dort steht danach der generische Typ.</summary>
    procedure NoteRewritten(ANode: TSyntaxNode);
    /// <summary>An AOffset steht danach der generische Typ (abgespaltene Deklaration).</summary>
    procedure NoteGenericAt(AOffset: Integer);
    /// <summary>Cast AOuter um AInner entfernen: davor und dahinter löschen, Edits im Inneren bleiben.</summary>
    procedure RemoveCast(AOuter, AInner: TSyntaxNode);
    /// <summary>Ein Contnrs-Typ steht außerhalb der umgeschriebenen Stellen (nicht als generischer Typ).</summary>
    function LegacyUnitStillUsed: Boolean;
    /// <summary>Der Text nennt den Bezeichner AName.</summary>
    function MentionsIdentifier(const AName: string): Boolean;
    /// <summary>Platzhalter einsetzen, sortieren, doppelte entfernen. False mit AReason, wenn sich Edits
    /// überschneiden.</summary>
    function Finalize(const AGenericText, AItemType: string; out AReason: string): Boolean;
    property Tree: TSyntaxTree read FTree;
    property Text: string read FText;
    property FileName: string read FFileName;
    property LineBreak: string read FLineBreak;
    property Edits: TArray<TTextEdit> read FEdits;
    /// <summary>Offsets, an denen der generische Typ neu im Text steht.</summary>
    property GenericAt: TArray<Integer> read FGenericAt;
    /// <summary>Bereiche der alten Klassennamen, die umgeschrieben werden.</summary>
    property Rewritten: TArray<TGenericListRange> read FRewritten;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.GenericLists.Kinds,
  Atlas.Common.Editing.GenericLists.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSourceText = (TheChangesInOverlap);

const
  cTexts: array[TSourceText] of TAtlasText = (
    (De: 'Die Änderungen in %s überschneiden sich'; En: 'The changes in %s overlap'));

{$SCOPEDENUMS OFF}

{ TGenericListRange }

function TGenericListRange.Contains(AOffset: Integer): Boolean;
begin
  Result := (AOffset >= StartOffset) and (AOffset < EndOffset);
end;

{ TGenericListSource }

constructor TGenericListSource.Create(ATree: TSyntaxTree; AOwnsTree: Boolean; const AText, AFileName: string);
begin
  inherited Create;
  FTree := ATree;
  FOwnsTree := AOwnsTree;
  FText := AText;
  FFileName := AFileName;
  FLineBreak := TTextLines.LineBreakOf(AText);
end;

destructor TGenericListSource.Destroy;
begin
  if FOwnsTree then
  begin
    FTree.Free;
  end;
  inherited;
end;

function TGenericListSource.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

procedure TGenericListSource.AddEdit(const AStart, AEnd: TTextPosition; const ANewText: string);
begin
  AddTextEdit(TTextEdit.Create(TTextRange.Create(AStart, AEnd), ANewText));
end;

procedure TGenericListSource.AddTextEdit(const AEdit: TTextEdit);
begin
  FEdits := FEdits + [AEdit];
end;

procedure TGenericListSource.NoteRewritten(ANode: TSyntaxNode);
var
  mRange: TGenericListRange;
begin
  mRange.StartOffset := ANode.StartOffset;
  mRange.EndOffset := ANode.EndOffset;
  FRewritten := FRewritten + [mRange];
  NoteGenericAt(ANode.StartOffset);
end;

procedure TGenericListSource.NoteGenericAt(AOffset: Integer);
begin
  FGenericAt := FGenericAt + [AOffset];
end;

procedure TGenericListSource.RemoveCast(AOuter, AInner: TSyntaxNode);
begin
  if AOuter.StartPos <> AInner.StartPos then
  begin
    AddEdit(AOuter.StartPos, AInner.StartPos, '');
  end;
  if AInner.EndPos <> AOuter.EndPos then
  begin
    AddEdit(AInner.EndPos, AOuter.EndPos, '');
  end;
end;

function TGenericListSource.IsRewritten(AOffset: Integer): Boolean;
var
  mRange: TGenericListRange;
begin
  for mRange in FRewritten do
  begin
    if mRange.Contains(AOffset) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TGenericListSource.ContnrsTypeKept(AIndex: Integer): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mNext: Integer;
begin
  mTokens := FTree.Tokens;
  if (mTokens[AIndex].Kind <> TPascalTokenKind.Identifier) or
    not TGenericListNames.IsContnrsType(mTokens[AIndex].Text) or IsRewritten(mTokens[AIndex].Offset) then
  begin
    Exit(False);
  end;
  // TStack<T> und TObjectList<T> stammen aus System.Generics.Collections.
  mNext := AIndex + 1;
  while (mNext <= High(mTokens)) and IsTrivia(mTokens[mNext]) do
  begin
    Inc(mNext);
  end;
  Result := (mNext > High(mTokens)) or not mTokens[mNext].IsSymbol('<');
end;

function TGenericListSource.LegacyUnitStillUsed: Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FTree.Tokens) do
  begin
    if ContnrsTypeKept(mIndex) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TGenericListSource.MentionsIdentifier(const AName: string): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in FTree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TGenericListSource.EditBefore(const AFirst, ASecond: TTextEdit): Boolean;
begin
  Result := (AFirst.Range.StartPos.Line < ASecond.Range.StartPos.Line) or
    ((AFirst.Range.StartPos.Line = ASecond.Range.StartPos.Line) and
    (AFirst.Range.StartPos.Character < ASecond.Range.StartPos.Character));
end;

class function TGenericListSource.SameEdit(const AFirst, ASecond: TTextEdit): Boolean;
begin
  Result := (AFirst.Range.StartPos = ASecond.Range.StartPos) and (AFirst.Range.EndPos = ASecond.Range.EndPos) and
    (AFirst.NewText = ASecond.NewText);
end;

function TGenericListSource.SortedEdits(const AGenericText, AItemType: string): TArray<TTextEdit>;
var
  mIndex, mInner: Integer;
  mEdit: TTextEdit;
begin
  Result := nil;
  for mEdit in FEdits do
  begin
    Result := Result + [TTextEdit.Create(mEdit.Range, StringReplace(StringReplace(mEdit.NewText,
      cGenericPlaceholder, AGenericText, [rfReplaceAll]), cItemPlaceholder, AItemType, [rfReplaceAll]))];
  end;
  // Einfügen statt TArray.Sort: stabil, Edits an derselben Stelle behalten ihre Reihenfolge.
  for mIndex := 1 to High(Result) do
  begin
    mEdit := Result[mIndex];
    mInner := mIndex - 1;
    while (mInner >= 0) and EditBefore(mEdit, Result[mInner]) do
    begin
      Result[mInner + 1] := Result[mInner];
      Dec(mInner);
    end;
    Result[mInner + 1] := mEdit;
  end;
end;

function TGenericListSource.Finalize(const AGenericText, AItemType: string; out AReason: string): Boolean;
var
  mEdit, mLast: TTextEdit;
  mSorted: TArray<TTextEdit>;
begin
  AReason := '';
  Result := True;
  mLast := Default(TTextEdit);
  mSorted := SortedEdits(AGenericText, AItemType);
  FEdits := nil;
  for mEdit in mSorted do
  begin
    if (FEdits <> nil) and SameEdit(mLast, mEdit) then
    begin
      Continue;
    end;
    if (FEdits <> nil) and not TGenericListSyntax.NotAfter(mLast.Range.EndPos, mEdit.Range.StartPos) then
    begin
      AReason := cTexts[TSourceText.TheChangesInOverlap].Fmt([ExtractFileName(FFileName)]);
      Exit(False);
    end;
    FEdits := FEdits + [mEdit];
    mLast := mEdit;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.GenericLists.Source', cTexts);

end.
