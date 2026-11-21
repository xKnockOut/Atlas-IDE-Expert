unit Atlas.Common.Editing.UsesClause;

// uses-Listen ergänzen und umschreiben (#180), ohne Protokollbezug; gelesen werden sie mit
// TPascalUses (Atlas.Common.Pascal.UsesClauses).
//
// - Rewrite (#284) schreibt die schlichten Listen neu: doppelte entfernen,
//   sortieren (alphabetisch, nach Namespace gruppiert oder nach Herkunft
//   gegliedert, #2794), Namen streichen. Listen mit Direktiven ({$IFDEF})
//   oder //-Kommentaren bleiben unberührt.
// - Nach Herkunft: je Gruppe (TUsesGroups) eine eigene Zeile, bei Bedarf
//   umbrochen, mit Gruppenkommentar { System } darüber, sobald es mehr als
//   eine Gruppe gibt. Alte Gruppenkommentare entfallen, andere Kommentare vor
//   dem ersten Eintrag bleiben.
//
// - Abschnitt: in einer Unit interface oder implementation, je nachdem, wo der
//   Cursor steht; in Programmen und Packages die uses nach dem Kopf.
// - Gibt es dort schon ein uses, kommt der Name vor dessen Semikolon; steht die
//   Liste über mehrere Zeilen, in eine eigene Zeile mit gleicher Einrückung.
//   Sonst entsteht hinter dem Abschnittswort ein neues uses.
// - Eine Unit gilt als eingebunden, wenn sie in einem der beiden uses steht,
//   auch ohne Namespace-Präfix (SysUtils für System.SysUtils, wenn "System"
//   zu den Namespaces des Projekts gehört).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Was Rewrite mit den Listen tut.</summary>
  TUsesRewrite = record
    Dedupe: Boolean;
    Sort: Boolean;
    /// <summary>Mit Sort: erst nach Namespace (System, Vcl, ...), Units ohne Namespace zuletzt.</summary>
    ByNamespace: Boolean;
    /// <summary>Diese Units entfallen.</summary>
    Drop: TArray<string>;
    /// <summary>Mit Sort: nach Herkunft gliedern (#2794); nil = nicht.</summary>
    GroupOf: TUsesGroupFunc;
    /// <summary>Darstellung der Gruppen mit GroupOf.</summary>
    GroupStyle: TUsesGroupStyle;
    /// <summary>Mit GroupOf: längere Zeilen einer Gruppe umbrechen; 0 = cDefaultLineLength.</summary>
    MaxLineLength: Integer;
  public const
    cDefaultLineLength = 120;
  end;

  TUsesClauses = class
  public
    /// <summary>Schreibt die schlichten Listen nach AOptions um; False ohne Änderung.</summary>
    class function Rewrite(const ATokens: TArray<TPascalToken>; const AText: string; const AOptions: TUsesRewrite;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Edit, das AUnitName in das uses des Abschnitts an AOffset einträgt;
    /// False, wenn kein passender Abschnitt gefunden wird.</summary>
    class function AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnitName: string;
      const ALineBreak: string; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Räumt die uses-Listen auf (#182): doppelte Einträge entfernen, auch solche im
    /// implementation-uses, die schon im interface stehen; mit ASort alphabetisch sortieren.
    /// Listen mit Direktiven oder //-Kommentaren bleiben unangetastet. False ohne Änderung.</summary>
    class function Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>; AByNamespace: Boolean): Boolean; overload; static;
    /// <summary>Wie oben mit AByNamespace = False.</summary>
    class function Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; overload; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.UsesClauses,
  Atlas.Common.Editing.UsesGroups,
  System.StrUtils;

type
  TUsesItem = record
    Name: string;
    Text: string;
    Order: Integer;
    /// <summary>Nur beim Gliedern nach Herkunft gesetzt.</summary>
    Group: TUsesGroup;
  end;

function TokenEnd(const AToken: TPascalToken): Integer;
begin
  Result := AToken.Offset + Length(AToken.Text);
end;

/// <summary>Sortierschlüssel der Gruppe: Namespace, Units ohne Namespace zuletzt.</summary>
function GroupOf(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := Pos('.', AName);
  if mDot = 0 then
  begin
    Result := #$FFFF;
  end
  else
  begin
    Result := Copy(AName, 1, mDot - 1);
  end;
end;

function ItemLess(const A, B: TUsesItem; AByNamespace: Boolean): Boolean;
var
  mCompared: Integer;
begin
  mCompared := 0;
  if AByNamespace then
  begin
    mCompared := CompareText(GroupOf(A.Name), GroupOf(B.Name));
  end;
  if mCompared = 0 then
  begin
    mCompared := CompareText(A.Name, B.Name);
  end;
  Result := (mCompared < 0) or ((mCompared = 0) and (A.Order < B.Order));
end;

/// <summary>Stabiles Sortieren durch Einfügen; uses-Listen sind kurz.</summary>
procedure SortItems(var AItems: TArray<TUsesItem>; AByNamespace: Boolean);
var
  I, J: Integer;
  mItem: TUsesItem;
begin
  for I := 1 to High(AItems) do
  begin
    mItem := AItems[I];
    J := I - 1;
    while (J >= 0) and ItemLess(mItem, AItems[J], AByNamespace) do
    begin
      AItems[J + 1] := AItems[J];
      Dec(J);
    end;
    AItems[J + 1] := mItem;
  end;
end;

function GroupedLess(const A, B: TUsesItem): Boolean;
var
  mCompared: Integer;
begin
  mCompared := Ord(A.Group) - Ord(B.Group);
  if mCompared = 0 then
  begin
    mCompared := CompareText(A.Name, B.Name);
  end;
  Result := (mCompared < 0) or ((mCompared = 0) and (A.Order < B.Order));
end;

/// <summary>Stabil nach Gruppe, dann Name (#2794).</summary>
procedure SortGrouped(var AItems: TArray<TUsesItem>);
var
  I, J: Integer;
  mItem: TUsesItem;
begin
  for I := 1 to High(AItems) do
  begin
    mItem := AItems[I];
    J := I - 1;
    while (J >= 0) and GroupedLess(mItem, AItems[J]) do
    begin
      AItems[J + 1] := AItems[J];
      Dec(J);
    end;
    AItems[J + 1] := mItem;
  end;
end;

class function TUsesClauses.AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
  const AUnitName, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mStart, mUsesIndex, mSemicolon, mLastName: Integer;
  mNames: TArray<string>;
  mIndent: string;
begin
  mStart := TPascalUses.SectionStart(ATokens, AOffset);
  if mStart < 0 then
  begin
    Exit(False);
  end;
  mUsesIndex := NextCodeAfter(ATokens, mStart);
  if (mUsesIndex <= High(ATokens)) and (ATokens[mUsesIndex].IsKeyword('uses')) then
  begin
    mNames := nil;
    mSemicolon := TPascalUses.ReadNames(ATokens, mUsesIndex, mNames);
    if mSemicolon < 0 then
    begin
      Exit(False);
    end;
    mLastName := mSemicolon - 1;
    while (mLastName > mUsesIndex) and IsTrivia(ATokens[mLastName]) do
    begin
      Dec(mLastName);
    end;
    if ATokens[mLastName].StartPos.Line > ATokens[mUsesIndex].StartPos.Line then
    begin
      // Mehrzeilige Liste: eigene Zeile, eingerückt wie die Zeile des letzten Eintrags.
      while (mLastName > mUsesIndex) and (ATokens[mLastName - 1].StartPos.Line = ATokens[mLastName].StartPos.Line) do
      begin
        Dec(mLastName);
      end;
      mIndent := StringOfChar(' ', ATokens[mLastName].StartPos.Character);
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mSemicolon].StartPos, ATokens[mSemicolon].StartPos),
        ',' + ALineBreak + mIndent + AUnitName);
    end
    else
    begin
      AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mSemicolon].StartPos, ATokens[mSemicolon].StartPos),
        ', ' + AUnitName);
    end;
    Exit(True);
  end;
  AEdit := TTextEdit.Create(TTextRange.Create(ATokens[mStart].EndPos, ATokens[mStart].EndPos),
    ALineBreak + ALineBreak + 'uses' + ALineBreak + '  ' + AUnitName + ';');
  Result := True;
end;

class function TUsesClauses.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
  const ALineBreak: string; out AEdits: TArray<TTextEdit>; AByNamespace: Boolean): Boolean;
var
  mOptions: TUsesRewrite;
begin
  mOptions := Default(TUsesRewrite);
  mOptions.Dedupe := True;
  mOptions.Sort := ASort;
  mOptions.ByNamespace := AByNamespace;
  Result := Rewrite(ATokens, AText, mOptions, ALineBreak, AEdits);
end;

/// <summary>Eintrag ab ACursor bis zum nächsten Komma (bzw. ASemicolon) mit seinem Quelltext; ACursor steht
/// danach auf dem Komma bzw. auf ASemicolon.</summary>
function ReadItem(const ATokens: TArray<TPascalToken>; const AText: string; var ACursor: Integer;
  ASemicolon: Integer): TUsesItem;
var
  mFirst, mLast: Integer;
  mAfterIn: Boolean;
begin
  Result := Default(TUsesItem);
  mFirst := ACursor;
  mLast := ACursor;
  mAfterIn := False;
  while (ACursor < ASemicolon) and not ATokens[ACursor].IsSymbol(',') do
  begin
    if ATokens[ACursor].IsKeyword('in') then
    begin
      mAfterIn := True;
    end
    else if not mAfterIn and ((ATokens[ACursor].Kind = TPascalTokenKind.Identifier) or
      ATokens[ACursor].IsSymbol('.')) then
    begin
      Result.Name := Result.Name + ATokens[ACursor].Text;
    end;
    mLast := ACursor;
    Inc(ACursor);
  end;
  Result.Text := Copy(AText, ATokens[mFirst].Offset + 1, TokenEnd(ATokens[mLast]) - ATokens[mFirst].Offset);
end;

/// <summary>Einträge der Liste zwischen uses (AIndex) und ASemicolon, Trennzeichen sind die Kommas.</summary>
function ReadItems(const ATokens: TArray<TPascalToken>; const AText: string; AIndex, ASemicolon: Integer):
  TArray<TUsesItem>;
var
  mCursor: Integer;
  mItem: TUsesItem;
begin
  Result := nil;
  mCursor := NextCodeAfter(ATokens, AIndex);
  while mCursor < ASemicolon do
  begin
    mItem := ReadItem(ATokens, AText, mCursor, ASemicolon);
    mItem.Order := Length(Result);
    Result := Result + [mItem];
    if mCursor < ASemicolon then
    begin
      mCursor := NextCodeAfter(ATokens, mCursor);
    end;
  end;
end;

/// <summary>Haben AKept andere Einträge oder eine andere Reihenfolge als AItems?</summary>
function OrderChanged(const AItems, AKept: TArray<TUsesItem>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AKept) <> Length(AItems);
  for mIndex := 0 to High(AKept) do
  begin
    if AKept[mIndex].Order <> mIndex then
    begin
      Result := True;
    end;
  end;
end;

/// <summary>Quelltext der Einträge AKept, getrennt durch ASeparator.</summary>
function JoinItems(const AKept: TArray<TUsesItem>; const ASeparator: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AKept) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ASeparator;
    end;
    Result := Result + AKept[mIndex].Text;
  end;
end;

type
  /// <summary>Zustand von TUsesClauses.Rewrite über alle Listen der Datei.</summary>
  TUsesRewriter = record
    Tokens: TArray<TPascalToken>;
    Text: string;
    Options: TUsesRewrite;
    LineBreak: string;
    /// <summary>Namen der bisherigen Listen (für Dedupe).</summary>
    Seen: TArray<string>;
    Edits: TArray<TTextEdit>;
    /// <summary>Behaltene Einträge, ohne Drop und (mit Dedupe) ohne schon gesehene.</summary>
    function Keep(const AItems: TArray<TUsesItem>): TArray<TUsesItem>;
    /// <summary>Edit für die Liste mit den Einträgen AKept; ohne Einträge entfällt die ganze Liste.</summary>
    function ListEdit(AIndex, ASemicolon: Integer; const AKept: TArray<TUsesItem>): TTextEdit;
    /// <summary>Text hinter uses (AIndex) bis vor das Semikolon nach Herkunft gegliedert (#2794).</summary>
    function GroupedText(AIndex: Integer; const AKept: TArray<TUsesItem>): string;
    /// <summary>Wie RewriteList, aber nach Herkunft gegliedert; Edit nur bei geändertem Text.</summary>
    procedure RewriteGrouped(AIndex, ASemicolon: Integer; const AKept: TArray<TUsesItem>);
    /// <summary>Schreibt die schlichte Liste zwischen uses (AIndex) und ASemicolon um.</summary>
    procedure RewriteList(AIndex, ASemicolon: Integer);
  end;

{ TUsesRewriter }

function TUsesRewriter.Keep(const AItems: TArray<TUsesItem>): TArray<TUsesItem>;
var
  mItem: TUsesItem;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if not MatchText(mItem.Name, Options.Drop) and not (Options.Dedupe and MatchText(mItem.Name, Seen)) then
    begin
      Result := Result + [mItem];
      Seen := Seen + [mItem.Name];
    end;
  end;
  if Options.Sort and not Assigned(Options.GroupOf) then
  begin
    SortItems(Result, Options.ByNamespace);
  end;
end;

function TUsesRewriter.ListEdit(AIndex, ASemicolon: Integer; const AKept: TArray<TUsesItem>): TTextEdit;
var
  mFirst, mLast: Integer;
  mSeparator: string;
begin
  if AKept = nil then
  begin
    Exit(TTextEdit.Create(TTextRange.Create(Tokens[AIndex].StartPos, Tokens[ASemicolon].EndPos), ''));
  end;
  mFirst := NextCodeAfter(Tokens, AIndex);
  // Bis zum Semikolon, damit ein Kommentar am letzten Eintrag nicht doppelt erscheint.
  mLast := ASemicolon - 1;
  mSeparator := ', ';
  if Tokens[mLast].StartPos.Line > Tokens[AIndex].StartPos.Line then
  begin
    mSeparator := ',' + LineBreak + StringOfChar(' ', Tokens[mFirst].StartPos.Character);
  end;
  Result := TTextEdit.Create(TTextRange.Create(Tokens[mFirst].StartPos, Tokens[mLast].EndPos),
    JoinItems(AKept, mSeparator));
end;

procedure TUsesRewriter.RewriteList(AIndex, ASemicolon: Integer);
var
  mItems, mKept: TArray<TUsesItem>;
begin
  mItems := ReadItems(Tokens, Text, AIndex, ASemicolon);
  if mItems = nil then
  begin
    Exit;
  end;
  mKept := Keep(mItems);
  if Options.Sort and Assigned(Options.GroupOf) then
  begin
    RewriteGrouped(AIndex, ASemicolon, mKept);
  end
  else if OrderChanged(mItems, mKept) then
  begin
    Edits := Edits + [ListEdit(AIndex, ASemicolon, mKept)];
  end;
end;

/// <summary>Einrückung der Einträge: Spalte des ersten Eintrags, wenn er unter uses steht, sonst zwei mehr als
/// uses.</summary>
function ItemIndent(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mFirst: Integer;
begin
  mFirst := NextCodeAfter(ATokens, AIndex);
  Result := ATokens[AIndex].StartPos.Character + 2;
  if (mFirst <= High(ATokens)) and (ATokens[mFirst].StartPos.Line > ATokens[AIndex].StartPos.Line) then
  begin
    Result := ATokens[mFirst].StartPos.Character;
  end;
end;

/// <summary>Kommentare zwischen uses (AIndex) und dem ersten Eintrag, die keine Gruppenkommentare sind.</summary>
function LeadingComments(const ATokens: TArray<TPascalToken>; AIndex: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := AIndex + 1;
  while (mIndex <= High(ATokens)) and IsTrivia(ATokens[mIndex]) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Comment) and not TUsesGroups.IsLabel(ATokens[mIndex].Text) then
    begin
      Result := Result + [ATokens[mIndex].Text];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Zeilen der Gruppe: Einträge mit Komma (außer ALast für den letzten Eintrag der Liste), umbrochen
/// vor AMaxLength.</summary>
function GroupLines(const AItems: TArray<string>; const AIndent: string; AMaxLength: Integer;
  ALastOfList: Boolean): TArray<string>;
var
  mIndex: Integer;
  mLine, mPart: string;
begin
  Result := nil;
  mLine := '';
  for mIndex := 0 to High(AItems) do
  begin
    mPart := AItems[mIndex];
    if not (ALastOfList and (mIndex = High(AItems))) then
    begin
      mPart := mPart + ',';
    end;
    if (mLine <> '') and (Length(mLine) + 1 + Length(mPart) > AMaxLength) then
    begin
      Result := Result + [mLine];
      mLine := '';
    end;
    if mLine = '' then
    begin
      mLine := AIndent + mPart;
    end
    else
    begin
      mLine := mLine + ' ' + mPart;
    end;
  end;
  if mLine <> '' then
  begin
    Result := Result + [mLine];
  end;
end;

/// <summary>Anzahl verschiedener Gruppen in den sortierten Einträgen.</summary>
function GroupCount(const AItems: TArray<TUsesItem>): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(AItems) do
  begin
    if (mIndex = 0) or (AItems[mIndex].Group <> AItems[mIndex - 1].Group) then
    begin
      Inc(Result);
    end;
  end;
end;

function TUsesRewriter.GroupedText(AIndex: Integer; const AKept: TArray<TUsesItem>): string;
var
  mIndent, mComment: string;
  mLines, mNames: TArray<string>;
  mFirst, mLast, mMaxLength: Integer;
  mLabels: Boolean;
begin
  mIndent := StringOfChar(' ', ItemIndent(Tokens, AIndex));
  mMaxLength := Options.MaxLineLength;
  if mMaxLength <= 0 then
  begin
    mMaxLength := TUsesRewrite.cDefaultLineLength;
  end;
  mLabels := (Options.GroupStyle = TUsesGroupStyle.Comments) and (GroupCount(AKept) > 1);
  mLines := nil;
  for mComment in LeadingComments(Tokens, AIndex) do
  begin
    mLines := mLines + [mIndent + mComment];
  end;
  mFirst := 0;
  while mFirst <= High(AKept) do
  begin
    mLast := mFirst;
    mNames := nil;
    while (mLast <= High(AKept)) and (AKept[mLast].Group = AKept[mFirst].Group) do
    begin
      mNames := mNames + [Trim(AKept[mLast].Text)];
      Inc(mLast);
    end;
    if mLabels then
    begin
      mLines := mLines + [mIndent + TUsesGroups.LabelOf(AKept[mFirst].Group)];
    end;
    mLines := mLines + GroupLines(mNames, mIndent, mMaxLength, mLast > High(AKept));
    mFirst := mLast;
  end;
  Result := LineBreak + string.Join(LineBreak, mLines);
end;

procedure TUsesRewriter.RewriteGrouped(AIndex, ASemicolon: Integer; const AKept: TArray<TUsesItem>);
var
  mSorted: TArray<TUsesItem>;
  mIndex, mStart: Integer;
  mOld, mNew: string;
begin
  if AKept = nil then
  begin
    Edits := Edits + [ListEdit(AIndex, ASemicolon, nil)];
    Exit;
  end;
  mSorted := Copy(AKept);
  for mIndex := 0 to High(mSorted) do
  begin
    mSorted[mIndex].Group := Options.GroupOf(mSorted[mIndex].Name);
  end;
  SortGrouped(mSorted);
  mNew := GroupedText(AIndex, mSorted);
  mStart := TokenEnd(Tokens[AIndex]);
  mOld := Copy(Text, mStart + 1, Tokens[ASemicolon].Offset - mStart);
  if mNew <> mOld then
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Tokens[AIndex].EndPos, Tokens[ASemicolon].StartPos),
      mNew)];
  end;
end;

class function TUsesClauses.Rewrite(const ATokens: TArray<TPascalToken>; const AText: string;
  const AOptions: TUsesRewrite; const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
var
  mIndex, mSemicolon: Integer;
  mNames: TArray<string>;
  mRewriter: TUsesRewriter;
begin
  mRewriter := Default(TUsesRewriter);
  mRewriter.Tokens := ATokens;
  mRewriter.Text := AText;
  mRewriter.Options := AOptions;
  mRewriter.LineBreak := ALineBreak;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if not ATokens[mIndex].IsKeyword('uses') then
    begin
      Inc(mIndex);
      Continue;
    end;
    mNames := nil;
    mSemicolon := TPascalUses.ReadNames(ATokens, mIndex, mNames);
    if mSemicolon < 0 then
    begin
      Break;
    end;
    if TPascalUses.IsPlainList(ATokens, mIndex + 1, mSemicolon - 1) then
    begin
      mRewriter.RewriteList(mIndex, mSemicolon);
    end
    else
    begin
      // Unangetastet, aber die Namen zählen für spätere Listen.
      mRewriter.Seen := mRewriter.Seen + mNames;
    end;
    mIndex := mSemicolon + 1;
  end;
  AEdits := mRewriter.Edits;
  Result := AEdits <> nil;
end;

class function TUsesClauses.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
  const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
begin
  Result := Organize(ATokens, AText, ASort, ALineBreak, AEdits, False);
end;

end.
