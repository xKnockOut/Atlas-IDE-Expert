unit Atlas.Common.Editing.UsesClause;

// uses-Listen lesen und ergänzen (#180), ohne Protokollbezug.
//
// - Rewrite (#284) schreibt die schlichten Listen neu: doppelte entfernen,
//   sortieren (alphabetisch oder nach Namespace gruppiert), Namen streichen.
//   Listen mit Direktiven ({$IFDEF}) oder //-Kommentaren bleiben unberührt.
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
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Art der Liste: uses bindet ein, contains (Package) nimmt auf, requires (Package) braucht ein
  /// Package.</summary>
  TUsesListKind = (UsesList, ContainsList, RequiresList);

  /// <summary>Eintrag einer uses-, contains- oder requires-Liste mit Position (#183).</summary>
  TUsesReference = record
    Name: string;
    Range: TTextRange;
    List: TUsesListKind;
    /// <summary>Steht im interface-Teil einer Unit (#268); in Programmen, Packages und im
    /// implementation-Teil False.</summary>
    InInterface: Boolean;
  end;

  /// <summary>Eine uses-Liste (#284).</summary>
  TUsesClauseInfo = record
    /// <summary>Token-Index von "uses" und vom abschließenden Semikolon.</summary>
    UsesIndex: Integer;
    Semicolon: Integer;
    Names: TArray<string>;
    /// <summary>Im interface einer Unit.</summary>
    InInterface: Boolean;
    /// <summary>Ohne Direktiven und //-Kommentare; nur solche Listen werden umgeschrieben.</summary>
    Plain: Boolean;
  end;

  /// <summary>Was Rewrite mit den Listen tut.</summary>
  TUsesRewrite = record
    Dedupe: Boolean;
    Sort: Boolean;
    /// <summary>Mit Sort: erst nach Namespace (System, Vcl, ...), Units ohne Namespace zuletzt.</summary>
    ByNamespace: Boolean;
    /// <summary>Diese Units entfallen.</summary>
    Drop: TArray<string>;
  end;

  TUsesClauses = class
  public
    /// <summary>Alle uses-Listen (nicht requires/contains) in Reihenfolge.</summary>
    class function Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>; static;
    /// <summary>Liegt AOffset zwischen uses und Semikolon einer der Listen AClauses?</summary>
    class function InClause(const ATokens: TArray<TPascalToken>; const AClauses: TArray<TUsesClauseInfo>;
      AOffset: Integer): Boolean; static;
    /// <summary>Schreibt die schlichten Listen nach AOptions um; False ohne Änderung.</summary>
    class function Rewrite(const ATokens: TArray<TPascalToken>; const AText: string; const AOptions: TUsesRewrite;
      const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean; static;
    /// <summary>Alle Unit-Namen aus den uses-Listen (interface und implementation).</summary>
    class function UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>; static;
    /// <summary>True, wenn die Unit ein Test-Framework einbindet (DUnitX.TestFramework, TestFramework
    /// oder TestInsight.*). Hier statt in Rules.Profiles, damit Editing ohne Rules auskommt (A-11).</summary>
    class function IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean; static;
    /// <summary>Nennt AUsed ein Testframework (DUnitX.TestFramework, TestFramework, TestInsight.*)? Wie
    /// IsTestUnit, aber aus den uses-Listen des Index statt aus dem Quelltext.</summary>
    class function UsesTestFramework(const AUsed: TArray<string>): Boolean; static;
    /// <summary>Alle Einträge aus uses, contains und requires mit Position, in Quelltextreihenfolge.</summary>
    class function References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>; static;
    /// <summary>Name der eigenen Unit bzw. des Programms; '' wenn unbekannt.</summary>
    class function OwnName(const ATokens: TArray<TPascalToken>): string; static;
    /// <summary>True, wenn AUnitName eingebunden ist, auch über einen der Namespaces.</summary>
    class function IsUsed(const AUsed: TArray<string>; const AUnitName: string;
      const ANamespaces: TArray<string>): Boolean; static;
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

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextIndex(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Index des Semikolons, das die Anweisung ab AIndex abschließt; -1 ohne.</summary>
function SemicolonAfter(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while Result <= High(ATokens) do
  begin
    if ATokens[Result].IsSymbol(';') then
    begin
      Exit;
    end;
    Inc(Result);
  end;
  Result := -1;
end;

/// <summary>Erstes Token (nicht Trivia); -1 bei leerem Text.</summary>
function FirstIndex(const ATokens: TArray<TPascalToken>): Integer;
begin
  Result := NextIndex(ATokens, -1);
  if Result > High(ATokens) then
  begin
    Result := -1;
  end;
end;

/// <summary>Index des Abschnittsworts (interface/implementation) bzw. des Semikolons
/// hinter dem Programmkopf; -1, wenn nicht vorhanden.</summary>
function SectionStart(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  mFirst, mHeaderEnd, mIndex, mInterface_, mImplementation_: Integer;
begin
  Result := -1;
  mFirst := FirstIndex(ATokens);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mHeaderEnd := SemicolonAfter(ATokens, mFirst);
  if mHeaderEnd < 0 then
  begin
    Exit;
  end;
  if not ATokens[mFirst].IsKeyword('unit') then
  begin
    // program, library, package: ein uses (bzw. contains) hinter dem Kopf.
    Exit(mHeaderEnd);
  end;
  mInterface_ := NextIndex(ATokens, mHeaderEnd);
  if (mInterface_ > High(ATokens)) or not ATokens[mInterface_].IsKeyword('interface') then
  begin
    Exit;
  end;
  mImplementation_ := -1;
  for mIndex := mInterface_ + 1 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mImplementation_ := mIndex;
      Break;
    end;
  end;
  if (mImplementation_ >= 0) and (AOffset >= ATokens[mImplementation_].Offset) then
  begin
    Result := mImplementation_;
  end
  else
  begin
    Result := mInterface_;
  end;
end;

function ReadNames(const ATokens: TArray<TPascalToken>; AUses: Integer; var ANames: TArray<string>): Integer;
var
  mIndex: Integer;
  mName: string;
  mAfterIn: Boolean;
begin
  // uses A, B.C in 'b.pas', D; liefert den Index des Semikolons.
  mIndex := AUses + 1;
  mName := '';
  mAfterIn := False;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol(';') or ATokens[mIndex].IsSymbol(',') then
    begin
      if mName <> '' then
      begin
        ANames := ANames + [mName];
      end;
      mName := '';
      mAfterIn := False;
      if ATokens[mIndex].IsSymbol(';') then
      begin
        Exit(mIndex);
      end;
    end
    else if ATokens[mIndex].IsKeyword('in') then
    begin
      mAfterIn := True;
    end
    else if not mAfterIn and ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol('.')) then
    begin
      mName := mName + ATokens[mIndex].Text;
    end;
    Inc(mIndex);
  end;
  Result := -1;
end;

{ TUsesClauses }

class function TUsesClauses.IsTestUnit(const ATokens: TArray<TPascalToken>): Boolean;
begin
  Result := UsesTestFramework(UsedUnits(ATokens));
end;

class function TUsesClauses.UsesTestFramework(const AUsed: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in AUsed do
  begin
    if SameText(mName, 'DUnitX.TestFramework') or SameText(mName, 'TestFramework') or
      mName.StartsWith('TestInsight.', True) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUsesClauses.UsedUnits(const ATokens: TArray<TPascalToken>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('uses') or ATokens[mIndex].IsKeyword('requires') then
    begin
      mIndex := ReadNames(ATokens, mIndex, Result);
      if mIndex < 0 then
      begin
        Exit;
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>True am Anfang einer uses-, contains- oder requires-Liste. contains und
/// requires sind keine reservierten Wörter, nur am Anweisungsanfang gemeint.</summary>
function IsListStart(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrevious: Integer;
begin
  if ATokens[AIndex].IsKeyword('uses') or ATokens[AIndex].IsKeyword('requires') or
    ATokens[AIndex].IsKeyword('contains') then
  begin
    Exit(True);
  end;
  if not ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    (SameText(ATokens[AIndex].Text, 'contains') or SameText(ATokens[AIndex].Text, 'requires'))) then
  begin
    Exit(False);
  end;
  mPrevious := AIndex - 1;
  while (mPrevious >= 0) and IsTrivia(ATokens[mPrevious]) do
  begin
    Dec(mPrevious);
  end;
  Result := (mPrevious >= 0) and ATokens[mPrevious].IsSymbol(';');
end;

/// <summary>Token-Index von "implementation"; Length(ATokens) ohne.</summary>
function ImplementationIndex(const ATokens: TArray<TPascalToken>): Integer;
var
  mIndex: Integer;
begin
  Result := Length(ATokens);
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Art der Liste zum Schlüsselwort AToken (uses, contains, requires).</summary>
function ListKindOf(const AToken: TPascalToken): TUsesListKind;
begin
  Result := TUsesListKind.UsesList;
  if SameText(AToken.Text, 'contains') then
  begin
    Result := TUsesListKind.ContainsList;
  end
  else if SameText(AToken.Text, 'requires') then
  begin
    Result := TUsesListKind.RequiresList;
  end;
end;

type
  /// <summary>Liest die Einträge einer Liste: uses A, B.C in 'b.pas', D; ein Eintrag je Name, Position über alle
  /// Namensteile.</summary>
  TReferenceReader = record
    Name: string;
    First: Integer;
    Last: Integer;
    AfterIn: Boolean;
    /// <summary>Vorlage mit List und InInterface.</summary>
    Reference: TUsesReference;
    /// <summary>Schließt den Eintrag am Komma bzw. Semikolon ab.</summary>
    procedure Flush(const ATokens: TArray<TPascalToken>; var AResult: TArray<TUsesReference>);
    /// <summary>Nimmt das Token an AIndex auf (Namensteil oder "in").</summary>
    procedure Take(const ATokens: TArray<TPascalToken>; AIndex: Integer);
  end;

procedure TReferenceReader.Flush(const ATokens: TArray<TPascalToken>; var AResult: TArray<TUsesReference>);
begin
  if Name <> '' then
  begin
    Reference.Name := Name;
    Reference.Range := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
    AResult := AResult + [Reference];
  end;
  Name := '';
  First := -1;
  AfterIn := False;
end;

procedure TReferenceReader.Take(const ATokens: TArray<TPascalToken>; AIndex: Integer);
begin
  if ATokens[AIndex].IsKeyword('in') then
  begin
    AfterIn := True;
  end
  else if not AfterIn and ((ATokens[AIndex].Kind = TPascalTokenKind.Identifier) or
    ATokens[AIndex].IsSymbol('.')) then
  begin
    if First < 0 then
    begin
      First := AIndex;
    end;
    Last := AIndex;
    Name := Name + ATokens[AIndex].Text;
  end;
end;

/// <summary>Liest die Liste, deren Schlüsselwort an AIndex steht, nach AResult; AIndex steht danach auf dem
/// abschließenden Semikolon (bzw. hinter dem letzten Token).</summary>
procedure ReadReferences(const ATokens: TArray<TPascalToken>; var AIndex: Integer; AInInterface: Boolean;
  var AResult: TArray<TUsesReference>);
var
  mReader: TReferenceReader;
begin
  mReader := Default(TReferenceReader);
  mReader.First := -1;
  mReader.Last := -1;
  mReader.Reference.InInterface := AInInterface;
  mReader.Reference.List := ListKindOf(ATokens[AIndex]);
  Inc(AIndex);
  while AIndex <= High(ATokens) do
  begin
    if ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsSymbol(',') then
    begin
      mReader.Flush(ATokens, AResult);
      if ATokens[AIndex].IsSymbol(';') then
      begin
        Break;
      end;
    end
    else
    begin
      mReader.Take(ATokens, AIndex);
    end;
    Inc(AIndex);
  end;
end;

class function TUsesClauses.References(const ATokens: TArray<TPascalToken>): TArray<TUsesReference>;
var
  mIndex, mFirst, mImplementation: Integer;
  mIsUnit: Boolean;
begin
  Result := nil;
  // Abschnitt je Eintrag (#268): in einer Unit gilt alles vor "implementation" als interface.
  mFirst := FirstIndex(ATokens);
  mIsUnit := (mFirst >= 0) and ATokens[mFirst].IsKeyword('unit');
  mImplementation := ImplementationIndex(ATokens);
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if IsListStart(ATokens, mIndex) then
    begin
      ReadReferences(ATokens, mIndex, mIsUnit and (mIndex < mImplementation), Result);
    end;
    Inc(mIndex);
  end;
end;

class function TUsesClauses.OwnName(const ATokens: TArray<TPascalToken>): string;
var
  mFirst, mHeaderEnd, mIndex: Integer;
begin
  Result := '';
  mFirst := FirstIndex(ATokens);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mHeaderEnd := SemicolonAfter(ATokens, mFirst);
  if mHeaderEnd < 0 then
  begin
    Exit;
  end;
  for mIndex := mFirst + 1 to mHeaderEnd - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or ATokens[mIndex].IsSymbol('.') then
    begin
      Result := Result + ATokens[mIndex].Text;
    end
    else if not IsTrivia(ATokens[mIndex]) then
    begin
      Break;
    end;
  end;
end;

class function TUsesClauses.IsUsed(const AUsed: TArray<string>; const AUnitName: string;
  const ANamespaces: TArray<string>): Boolean;
var
  mUsed, mNamespace: string;
begin
  for mUsed in AUsed do
  begin
    if SameText(mUsed, AUnitName) then
    begin
      Exit(True);
    end;
    for mNamespace in ANamespaces do
    begin
      if SameText(mNamespace + '.' + mUsed, AUnitName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

type
  TUsesItem = record
    Name: string;
    Text: string;
    Order: Integer;
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

function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>True, wenn die Liste zwischen AFirst und ALast keine Direktive und keinen //-Kommentar enthält.</summary>
function IsPlainList(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst to ALast do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Directive) or
      ((ATokens[mIndex].Kind = TPascalTokenKind.Comment) and (Copy(ATokens[mIndex].Text, 1, 2) = '//')) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TUsesClauses.Clauses(const ATokens: TArray<TPascalToken>): TArray<TUsesClauseInfo>;
var
  mIndex: Integer;
  mIsUnit, mInImplementation: Boolean;
  mClause: TUsesClauseInfo;
begin
  Result := nil;
  mIndex := FirstIndex(ATokens);
  mIsUnit := (mIndex >= 0) and ATokens[mIndex].IsKeyword('unit');
  mInImplementation := False;
  mIndex := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsKeyword('implementation') then
    begin
      mInImplementation := True;
    end
    else if ATokens[mIndex].IsKeyword('uses') then
    begin
      mClause.UsesIndex := mIndex;
      mClause.Names := nil;
      mClause.Semicolon := ReadNames(ATokens, mIndex, mClause.Names);
      if mClause.Semicolon < 0 then
      begin
        Exit;
      end;
      mClause.InInterface := mIsUnit and not mInImplementation;
      mClause.Plain := IsPlainList(ATokens, mIndex + 1, mClause.Semicolon - 1);
      Result := Result + [mClause];
      mIndex := mClause.Semicolon;
    end;
    Inc(mIndex);
  end;
end;

class function TUsesClauses.Organize(const ATokens: TArray<TPascalToken>; const AText: string; ASort: Boolean;
  const ALineBreak: string; out AEdits: TArray<TTextEdit>): Boolean;
begin
  Result := Organize(ATokens, AText, ASort, ALineBreak, AEdits, False);
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

class function TUsesClauses.InClause(const ATokens: TArray<TPascalToken>;
  const AClauses: TArray<TUsesClauseInfo>; AOffset: Integer): Boolean;
var
  mClause: TUsesClauseInfo;
begin
  Result := False;
  for mClause in AClauses do
  begin
    if (AOffset > ATokens[mClause.UsesIndex].Offset) and (AOffset < ATokens[mClause.Semicolon].Offset) then
    begin
      Exit(True);
    end;
  end;
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
  mCursor := NextIndex(ATokens, AIndex);
  while mCursor < ASemicolon do
  begin
    mItem := ReadItem(ATokens, AText, mCursor, ASemicolon);
    mItem.Order := Length(Result);
    Result := Result + [mItem];
    if mCursor < ASemicolon then
    begin
      mCursor := NextIndex(ATokens, mCursor);
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
    /// <summary>Schreibt die schlichte Liste zwischen uses (AIndex) und ASemicolon um.</summary>
    procedure RewriteList(AIndex, ASemicolon: Integer);
  end;

function TUsesRewriter.Keep(const AItems: TArray<TUsesItem>): TArray<TUsesItem>;
var
  mItem: TUsesItem;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if not ContainsName(Options.Drop, mItem.Name) and not (Options.Dedupe and ContainsName(Seen, mItem.Name)) then
    begin
      Result := Result + [mItem];
      Seen := Seen + [mItem.Name];
    end;
  end;
  if Options.Sort then
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
  mFirst := NextIndex(Tokens, AIndex);
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
  if OrderChanged(mItems, mKept) then
  begin
    Edits := Edits + [ListEdit(AIndex, ASemicolon, mKept)];
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
    mSemicolon := ReadNames(ATokens, mIndex, mNames);
    if mSemicolon < 0 then
    begin
      Break;
    end;
    if IsPlainList(ATokens, mIndex + 1, mSemicolon - 1) then
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

class function TUsesClauses.AddUnit(const ATokens: TArray<TPascalToken>; AOffset: Integer;
  const AUnitName, ALineBreak: string; out AEdit: TTextEdit): Boolean;
var
  mStart, mUsesIndex, mSemicolon, mLastName: Integer;
  mNames: TArray<string>;
  mIndent: string;
begin
  mStart := SectionStart(ATokens, AOffset);
  if mStart < 0 then
  begin
    Exit(False);
  end;
  mUsesIndex := NextIndex(ATokens, mStart);
  if (mUsesIndex <= High(ATokens)) and (ATokens[mUsesIndex].IsKeyword('uses')) then
  begin
    mNames := nil;
    mSemicolon := ReadNames(ATokens, mUsesIndex, mNames);
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

end.
