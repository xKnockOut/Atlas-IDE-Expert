unit Atlas.Common.Pascal.UsesEdits;

// uses-Listen ergänzen und umschreiben (#180), ohne Protokollbezug; gelesen werden sie mit
// TPascalUses (Atlas.Common.Pascal.UsesClauses).
//
// - Rewrite (#284) schreibt die schlichten Listen neu: doppelte entfernen,
//   sortieren (alphabetisch, nach Namespace gruppiert oder nach Herkunft
//   gegliedert, #2794), Namen streichen. Listen mit Direktiven ({$IFDEF})
//   bleiben unberührt.
// - Kommentare in der Liste: Eine Kommentarzeile beginnt einen Abschnitt
//   (// Formulare); sortiert wird nur innerhalb der Abschnitte, die
//   Kommentarzeilen bleiben stehen. Ein Kommentar hinter einem Eintrag (in
//   derselben Zeile) wandert mit dem Eintrag. Ohne Sortieren bleibt die
//   Zeilenaufteilung, nur gestrichene Einträge entfallen.
// - Nach Herkunft: je Gruppe (TUsesGroups) eine eigene Zeile, bei Bedarf
//   umbrochen, mit Gruppenkommentar { System } darüber, sobald es mehr als
//   eine Gruppe gibt. Alte Gruppenkommentare entfallen, andere Kommentare vor
//   dem ersten Eintrag bleiben.
//
// - Abschnitt: in einer Unit interface oder implementation, je nachdem, wo der
//   Cursor steht; in Programmen und Packages die uses nach dem Kopf.
// - Gibt es dort schon ein uses, kommt der Name vor dessen Semikolon, hinter den
//   letzten Eintrag in dessen Zeile. Eine eigene Zeile mit gleicher Einrückung
//   bekommt er nur, wenn die mehrzeilige Liste einen Eintrag je Zeile führt
//   oder die letzte Zeile sonst zu lang würde.
//   Sonst entsteht hinter dem Abschnittswort ein neues uses.
// - Eine Unit gilt als eingebunden, wenn sie in einem der beiden uses steht,
//   auch ohne Namespace-Präfix (SysUtils für System.SysUtils, wenn "System"
//   zu den Namespaces des Projekts gehört).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
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

  TPascalUsesEdits = class
  public
    /// <summary>Schreibt die schlichten Listen nach AOptions um; False ohne Änderung.</summary>
    class function Rewrite(const ATokens: TArray<TPascalToken>; const AText: string; const AOptions: TUsesRewrite;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Edit, das AUnitName in das uses des Abschnitts an AOffset einträgt;
    /// False, wenn kein passender Abschnitt gefunden wird.</summary>
    class function AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnitName: string;
      const ALineBreak: string; out AEdit: TTextEdit): Boolean; static;
    /// <summary>Wie AddUnit, aber False, wenn AUnitName schon eingebunden ist (auch über ANamespaces oder ohne
    /// Namespace).</summary>
    class function AddMissingUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer; const AUnitName: string;
      const ANamespaces: TArray<string>; const ALineBreak: string; out AEdit: TTextEdit): Boolean; static;
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
  Atlas.Common.Pascal.UsesGroups,
  System.StrUtils;

type
  TUsesItem = record
    Name: string;
    Text: string;
    Order: Integer;
    /// <summary>Nur beim Gliedern nach Herkunft gesetzt.</summary>
    Group: TUsesGroup;
    /// <summary>Kommentar hinter dem Eintrag in derselben Zeile (nur in Listen mit Abschnitten).</summary>
    Comment: string;
    /// <summary>Zeile des Eintrags im Quelltext (nur in Listen mit Abschnitten).</summary>
    Line: Integer;
  end;

  /// <summary>Abschnitt einer uses-Liste: Kommentarzeilen darüber und die Einträge bis zum nächsten.</summary>
  TUsesSection = record
    Heading: TArray<string>;
    Items: TArray<TUsesItem>;
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

/// <summary>Steht jeder Eintrag der Liste zwischen uses (AUses) und ASemicolon in einer eigenen Zeile (mindestens
/// zwei Einträge, kein Komma mit einem Eintrag dahinter in derselben Zeile)?</summary>
function OnePerLine(const ATokens: TArray<TPascalToken>; AUses, ASemicolon: Integer): Boolean;
var
  mIndex, mNext, mCommas: Integer;
begin
  mCommas := 0;
  for mIndex := AUses + 1 to ASemicolon - 1 do
  begin
    if ATokens[mIndex].IsSymbol(',') then
    begin
      Inc(mCommas);
      mNext := NextCodeAfter(ATokens, mIndex);
      if (mNext < ASemicolon) and (ATokens[mNext].StartPos.Line = ATokens[mIndex].EndPos.Line) then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := mCommas > 0;
end;

/// <summary>Kommt ", AUnitName" hinter den letzten Eintrag (ALastName) in dessen Zeile? Ja, wenn die Liste nicht
/// einen Eintrag je Zeile führt, das Semikolon direkt dahinter in derselben Zeile steht (kein Kommentar dazwischen)
/// und die Zeile kürzer als TUsesRewrite.cDefaultLineLength bleibt.</summary>
function FitsBehind(const ATokens: TArray<TPascalToken>; AUses, ALastName, ASemicolon: Integer;
  const AUnitName: string): Boolean;
begin
  Result := (ASemicolon = ALastName + 1) and (ATokens[ASemicolon].StartPos.Line = ATokens[ALastName].EndPos.Line) and
    (ATokens[ASemicolon].StartPos.Character + Length(', ' + AUnitName + ';') <= TUsesRewrite.cDefaultLineLength) and
    not OnePerLine(ATokens, AUses, ASemicolon);
end;

class function TPascalUsesEdits.AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
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
    if (ATokens[mLastName].StartPos.Line > ATokens[mUsesIndex].StartPos.Line) and
      not FitsBehind(ATokens, mUsesIndex, mLastName, mSemicolon, AUnitName) then
    begin
      // Mehrzeilige Liste mit einem Eintrag je Zeile oder voller letzter Zeile: eigene Zeile, eingerückt wie die
      // Zeile des letzten Eintrags.
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

class function TPascalUsesEdits.AddMissingUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
  const AUnitName: string; const ANamespaces: TArray<string>; const ALineBreak: string;
  out AEdit: TTextEdit): Boolean;
var
  mUsed: TArray<string>;
  mShort: string;
begin
  mUsed := TPascalUses.UsedUnits(ATokens);
  mShort := Copy(AUnitName, LastDelimiter('.', AUnitName) + 1, MaxInt);
  if TPascalUses.IsUsed(mUsed, AUnitName, ANamespaces) or TPascalUses.IsUsed(mUsed, mShort, nil) then
  begin
    Exit(False);
  end;
  Result := AddUnit(ATokens, AOffset, AUnitName, ALineBreak, AEdit);
end;

class function TPascalUsesEdits.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
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
  /// <summary>Zustand von TPascalUsesEdits.Rewrite über alle Listen der Datei.</summary>
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
    /// <summary>Eintrag aus den Token AFirst bis ALast.</summary>
    function SectionItem(AFirst, ALast: Integer): TUsesItem;
    /// <summary>Abschnitte der Liste zwischen uses (AIndex) und ASemicolon.</summary>
    function ReadSections(AIndex, ASemicolon: Integer): TArray<TUsesSection>;
    /// <summary>Streicht und sortiert in jedem Abschnitt für sich.</summary>
    procedure ArrangeSections(var ASections: TArray<TUsesSection>);
    /// <summary>Zeilen der Abschnitte; AReflow füllt die Zeilen bis zur Zeilenlänge, sonst bleibt die
    /// Zeilenaufteilung des Quelltexts. Der letzte Eintrag trägt das Semikolon.</summary>
    function SectionLines(const ASections: TArray<TUsesSection>; const AIndent: string;
      AReflow: Boolean): TArray<string>;
    /// <summary>Wie RewriteList für eine Liste mit Kommentar-Abschnitten; ersetzt bis einschließlich Semikolon.
    /// </summary>
    procedure RewriteSections(AIndex, ASemicolon: Integer);
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

function IsLineComment(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Comment) and StartsStr('//', AToken.Text);
end;

/// <summary>Gruppenkommentar, den das Gliedern nach Herkunft selbst schreibt (und neu setzt)?</summary>
function IsOwnLabel(const AToken: TPascalToken; AGrouped: Boolean): Boolean;
begin
  Result := AGrouped and TUsesGroups.IsLabel(AToken.Text);
end;

/// <summary>Braucht die Liste zwischen uses (AIndex) und ASemicolon Abschnitte? Ja bei einem Kommentar hinter dem
/// ersten Eintrag, der nicht im Eintrag selbst steht (wie {Form1} hinter in 'Main.pas'): //-Kommentar, Kommentar
/// in eigener Zeile oder hinter einem Komma.</summary>
function HasSectionComments(const ATokens: TArray<TPascalToken>; AIndex, ASemicolon: Integer;
  AGrouped: Boolean): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := NextCodeAfter(ATokens, AIndex) + 1 to ASemicolon - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Comment) and not IsOwnLabel(ATokens[mIndex], AGrouped) and
      (IsLineComment(ATokens[mIndex]) or ATokens[mIndex - 1].IsSymbol(',') or
      (ATokens[mIndex].StartPos.Line > ATokens[mIndex - 1].EndPos.Line)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letztes Token des Eintrags ab AFirst vor dem Komma bzw. ASemicolon; ein //-Kommentar oder ein
/// Kommentar in einer späteren Zeile gehört nicht mehr dazu.</summary>
function SectionItemEnd(const ATokens: TArray<TPascalToken>; AFirst, ASemicolon: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := AFirst;
  mIndex := AFirst + 1;
  while (mIndex < ASemicolon) and not ATokens[mIndex].IsSymbol(',') do
  begin
    if IsLineComment(ATokens[mIndex]) or (ATokens[mIndex].StartPos.Line > ATokens[Result].EndPos.Line) then
    begin
      Break;
    end;
    Result := mIndex;
    Inc(mIndex);
  end;
end;

/// <summary>Kommentar AToken in die Abschnitte: in der Zeile des letzten Eintrags (ALine) hängt er an diesem,
/// sonst ist er eine Kommentarzeile, die einen neuen Abschnitt beginnt.</summary>
procedure AddSectionComment(var ASection: TUsesSection; var ASections: TArray<TUsesSection>;
  const AToken: TPascalToken; ALine: Integer);
var
  mLast: Integer;
begin
  mLast := High(ASection.Items);
  if (mLast >= 0) and (AToken.StartPos.Line = ALine) then
  begin
    if ASection.Items[mLast].Comment <> '' then
    begin
      ASection.Items[mLast].Comment := ASection.Items[mLast].Comment + ' ';
    end;
    ASection.Items[mLast].Comment := ASection.Items[mLast].Comment + AToken.Text;
    Exit;
  end;
  if mLast >= 0 then
  begin
    ASections := ASections + [ASection];
    ASection := Default(TUsesSection);
  end;
  ASection.Heading := ASection.Heading + [AToken.Text];
end;

function TUsesRewriter.SectionItem(AFirst, ALast: Integer): TUsesItem;
var
  mIndex: Integer;
  mAfterIn: Boolean;
begin
  Result := Default(TUsesItem);
  mAfterIn := False;
  for mIndex := AFirst to ALast do
  begin
    if Tokens[mIndex].IsKeyword('in') then
    begin
      mAfterIn := True;
    end
    else if not mAfterIn and ((Tokens[mIndex].Kind = TPascalTokenKind.Identifier) or Tokens[mIndex].IsSymbol('.')) then
    begin
      Result.Name := Result.Name + Tokens[mIndex].Text;
    end;
  end;
  Result.Text := Copy(Text, Tokens[AFirst].Offset + 1, TokenEnd(Tokens[ALast]) - Tokens[AFirst].Offset);
  Result.Line := Tokens[AFirst].StartPos.Line;
end;

function TUsesRewriter.ReadSections(AIndex, ASemicolon: Integer): TArray<TUsesSection>;
var
  mIndex, mLast, mLine: Integer;
  mSection: TUsesSection;
  mItem: TUsesItem;
begin
  Result := nil;
  mSection := Default(TUsesSection);
  // Zeile, in der der letzte Eintrag bzw. sein Komma endet: Kommentare dort hängen am Eintrag.
  mLine := -1;
  mIndex := AIndex + 1;
  while mIndex < ASemicolon do
  begin
    if Tokens[mIndex].IsSymbol(',') then
    begin
      mLine := Tokens[mIndex].EndPos.Line;
    end
    else if Tokens[mIndex].Kind = TPascalTokenKind.Comment then
    begin
      if not IsOwnLabel(Tokens[mIndex], Options.Sort and Assigned(Options.GroupOf)) then
      begin
        AddSectionComment(mSection, Result, Tokens[mIndex], mLine);
      end;
    end
    else
    begin
      mLast := SectionItemEnd(Tokens, mIndex, ASemicolon);
      mItem := SectionItem(mIndex, mLast);
      mItem.Order := Length(mSection.Items);
      mSection.Items := mSection.Items + [mItem];
      mLine := Tokens[mLast].EndPos.Line;
      mIndex := mLast;
    end;
    Inc(mIndex);
  end;
  Result := Result + [mSection];
end;

procedure TUsesRewriter.ArrangeSections(var ASections: TArray<TUsesSection>);
var
  mSection, mItem: Integer;
begin
  for mSection := 0 to High(ASections) do
  begin
    ASections[mSection].Items := Keep(ASections[mSection].Items);
    if Options.Sort and Assigned(Options.GroupOf) then
    begin
      for mItem := 0 to High(ASections[mSection].Items) do
      begin
        ASections[mSection].Items[mItem].Group := Options.GroupOf(ASections[mSection].Items[mItem].Name);
      end;
      SortGrouped(ASections[mSection].Items);
    end;
  end;
end;

/// <summary>Abschnitt und Stelle des letzten Eintrags; -1, wenn kein Eintrag bleibt.</summary>
function LastSection(const ASections: TArray<TUsesSection>): Integer;
begin
  Result := High(ASections);
  while (Result >= 0) and (ASections[Result].Items = nil) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Beginnt der Eintrag AItem eine neue Zeile? AReflow: bei voller Zeile oder neuer Gruppe (AGrouped);
/// sonst, wo er auch im Quelltext in einer neuen Zeile stand.</summary>
function StartsLine(const ALine, APiece: string; const AItem, APrevious: TUsesItem; AReflow, AGrouped: Boolean;
  AMaxLength: Integer): Boolean;
begin
  if ALine = '' then
  begin
    Result := False;
  end
  else if AReflow then
  begin
    Result := (AGrouped and (AItem.Group <> APrevious.Group)) or (Length(ALine) + 1 + Length(APiece) > AMaxLength);
  end
  else
  begin
    Result := AItem.Line <> APrevious.Line;
  end;
end;

/// <summary>Hängt die angefangene Zeile ALine an ALines an (wenn es eine gibt) und leert sie.</summary>
procedure FlushLine(var ALines: TArray<string>; var ALine: string);
begin
  if ALine <> '' then
  begin
    ALines := ALines + [ALine];
    ALine := '';
  end;
end;

/// <summary>Setzt APiece (Eintrag mit Komma bzw. Semikolon) und den Kommentar AComment in die Zeile ALine; hinter
/// einem //-Kommentar geht es in der nächsten Zeile weiter.</summary>
procedure PutPiece(var ALines: TArray<string>; var ALine: string; const AIndent, APiece, AComment: string);
begin
  if ALine = '' then
  begin
    ALine := AIndent + APiece;
  end
  else
  begin
    ALine := ALine + ' ' + APiece;
  end;
  if AComment <> '' then
  begin
    ALine := ALine + ' ' + AComment;
    if Pos('//', AComment) > 0 then
    begin
      FlushLine(ALines, ALine);
    end;
  end;
end;

function TUsesRewriter.SectionLines(const ASections: TArray<TUsesSection>; const AIndent: string;
  AReflow: Boolean): TArray<string>;
var
  mLastSection, mSection, mIndex, mMaxLength: Integer;
  mLine, mPiece, mHeading: string;
  mItems: TArray<TUsesItem>;
begin
  Result := nil;
  mMaxLength := Options.MaxLineLength;
  if mMaxLength <= 0 then
  begin
    mMaxLength := TUsesRewrite.cDefaultLineLength;
  end;
  mLastSection := LastSection(ASections);
  mLine := '';
  for mSection := 0 to High(ASections) do
  begin
    // Jeder Abschnitt beginnt eine neue Zeile.
    FlushLine(Result, mLine);
    for mHeading in ASections[mSection].Heading do
    begin
      Result := Result + [AIndent + mHeading];
    end;
    mItems := ASections[mSection].Items;
    for mIndex := 0 to High(mItems) do
    begin
      mPiece := mItems[mIndex].Text + ',';
      if (mSection = mLastSection) and (mIndex = High(mItems)) then
      begin
        mPiece := mItems[mIndex].Text + ';';
      end;
      if (mIndex > 0) and StartsLine(mLine, mPiece, mItems[mIndex], mItems[mIndex - 1], AReflow,
        Assigned(Options.GroupOf), mMaxLength) then
      begin
        FlushLine(Result, mLine);
      end;
      PutPiece(Result, mLine, AIndent, mPiece, mItems[mIndex].Comment);
    end;
  end;
  FlushLine(Result, mLine);
end;

procedure TUsesRewriter.RewriteSections(AIndex, ASemicolon: Integer);
var
  mSections: TArray<TUsesSection>;
  mLines: TArray<string>;
  mIndent, mOld, mNew: string;
  mStart: Integer;
begin
  mSections := ReadSections(AIndex, ASemicolon);
  ArrangeSections(mSections);
  mIndent := StringOfChar(' ', ItemIndent(Tokens, AIndex));
  mLines := SectionLines(mSections, mIndent, Options.Sort);
  if LastSection(mSections) < 0 then
  begin
    // Kein Eintrag bleibt: uses entfällt, die Kommentarzeilen bleiben stehen.
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Tokens[AIndex].StartPos, Tokens[ASemicolon].EndPos),
      TrimLeft(string.Join(LineBreak, mLines)))];
    Exit;
  end;
  mNew := LineBreak + string.Join(LineBreak, mLines);
  if not Options.Sort and (Tokens[NextCodeAfter(Tokens, AIndex)].StartPos.Line = Tokens[AIndex].StartPos.Line) then
  begin
    // Liste begann hinter uses: dort bleibt sie.
    mNew := ' ' + TrimLeft(string.Join(LineBreak, mLines));
  end;
  mStart := TokenEnd(Tokens[AIndex]);
  mOld := Copy(Text, mStart + 1, TokenEnd(Tokens[ASemicolon]) - mStart);
  if mNew <> mOld then
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Tokens[AIndex].EndPos, Tokens[ASemicolon].EndPos), mNew)];
  end;
end;

class function TPascalUsesEdits.Rewrite(const ATokens: TArray<TPascalToken>; const AText: string;
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
    if TPascalUses.HasDirectives(ATokens, mIndex + 1, mSemicolon - 1) then
    begin
      // Unangetastet, aber die Namen zählen für spätere Listen.
      mRewriter.Seen := mRewriter.Seen + mNames;
    end
    else if HasSectionComments(ATokens, mIndex, mSemicolon, AOptions.Sort and Assigned(AOptions.GroupOf)) then
    begin
      mRewriter.RewriteSections(mIndex, mSemicolon);
    end
    else
    begin
      mRewriter.RewriteList(mIndex, mSemicolon);
    end;
    mIndex := mSemicolon + 1;
  end;
  AEdits := mRewriter.Edits;
  Result := AEdits <> nil;
end;

class function TPascalUsesEdits.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
  const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
begin
  Result := Organize(ATokens, AText, ASort, ALineBreak, AEdits, False);
end;

end.
