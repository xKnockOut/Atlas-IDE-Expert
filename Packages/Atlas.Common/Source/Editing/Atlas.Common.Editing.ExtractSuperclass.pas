unit Atlas.Common.Editing.ExtractSuperclass;

// „Basisklasse herauslösen“ (#713): Gewählte Felder, Methoden und Properties
// einer Klasse wandern in eine neue Vorfahrklasse, die direkt über der Klasse
// in derselben Unit entsteht (eine neue Unit macht daraus
// Atlas.Common.Lsp.ExtractSuperclass über „Klasse verschieben“).
//
//   - Die neue Klasse erbt vom bisherigen Vorfahren (ohne Interfaces), die
//     Klasse von der neuen; Interfaces bleiben bei der Klasse.
//   - Je Methode „verschieben“ (Deklaration und Rumpf wandern) oder
//     „abstrakt“ (oben virtual; abstract;, unten override, der Rumpf bleibt).
//   - Abhängigkeiten: Ein verschobenes Mitglied darf nur Mitglieder benutzen,
//     die mitwandern (abstrakte Methoden zählen); sonst nennt der Plan sie.
//   - Sichtbarkeit: Ein strict-private-Mitglied, das oben landet und unten
//     weiter benutzt wird, wird protected bzw. strict protected (Einstellung);
//     ein private-Mitglied nur, wenn die Basisklasse in eine andere Unit kommt
//     (in derselben Unit sieht die Klasse es ohnehin) oder Code außerhalb der
//     Klasse es dort benutzt.
//   - Konstruktoren und Destruktoren: Setzen die Anweisungen direkt hinter
//     inherited Felder, die wandern, bekommt die Basisklasse einen
//     Konstruktor mit derselben Signatur und diesen Anweisungen; die Klasse
//     ruft ihn mit inherited auf. Beim Destruktor entsprechend die
//     Anweisungen direkt vor inherited. Wandern nur Anweisungen, die keine
//     lokalen Variablen und keine bleibenden Mitglieder benutzen, damit die
//     Reihenfolge erhalten bleibt.
//
// Gerechnet wird in Schritten (Änderungen anwenden, neu parsen): erst die
// Klasse ändern, dann die gehobenen abstrakten Methoden umsetzen, zuletzt die
// Basisklasse und ihre Rümpfe einfügen. Ergebnis ist der neue Text der Unit.

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout,
  Atlas.Common.Editing.MemberTransfer,
  Atlas.Common.Editing.ExtractInterface;

type
  /// <summary>Ist AName ein Interface (für den ersten Eintrag der Vorfahrenliste)?</summary>
  TIsInterfaceType = reference to function(const AName: string): Boolean;

  TSuperclassInfo = record
    ClassName: string;
    SuggestedName: string;
    /// <summary>Bisheriger Vorfahr (ohne Interfaces); '' ohne.</summary>
    Ancestor: string;
    Candidates: TArray<TTransferCandidate>;
    Notes: TArray<string>;
  end;

  TSuperclassRequest = record
    Name: string;
    /// <summary>Ids der gewählten Mitglieder.</summary>
    Members: TArray<Integer>;
    /// <summary>Ids der Methoden, die oben abstrakt werden (Teilmenge von Members).</summary>
    Abstract: TArray<Integer>;
    /// <summary>Die Basisklasse bleibt in der Unit der Klasse.</summary>
    SameUnit: Boolean;
    /// <summary>Protected_ oder StrictProtected.</summary>
    RaiseVisibility: TClassVisibility;
  end;

  TSuperclassPlan = record
    ClassName: string;
    BaseName: string;
    /// <summary>Neuer Text der Unit samt Basisklasse.</summary>
    Text: string;
    /// <summary>Kopfzeile der Basisklasse in Text.</summary>
    BaseLine: Integer;
    Moved: TArray<string>;
    Abstracts: TArray<string>;
    /// <summary>Gehobene private-Mitglieder.</summary>
    Raised: TArray<string>;
    /// <summary>Aufgeteilte Konstruktoren und Destruktoren.</summary>
    Split: TArray<string>;
    Warnings: TArray<string>;
  end;

  TExtractSuperclass = class
  public const
    Kind = 'refactor.extract';
  public
    /// <summary>Vorgeschlagener Name: ohne T, ohne erstes Wort bei mehreren, mit ASuffix (TPdfExport →
    /// TExportBase); ASuffix Custom wird Präfix (TCustomExport).</summary>
    class function SuggestName(const AClassName, ASuffix: string): string; static;
    /// <summary>Klasse auf der Kopfzeile ALine; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
    /// <summary>Kandidaten und Vorschlag; False mit Grund ohne Klasse oder ohne Kandidaten.</summary>
    class function Prepare(const ASource: TClassSource; const ASuffix: string; const ANameInUse: TNameInUse;
      out AInfo: TSuperclassInfo; out AReason: string): Boolean; static;
    /// <summary>Neuer Text der Unit für ARequest; False mit Grund (Name, Auswahl, Abhängigkeiten).</summary>
    class function Plan(const ASource: TClassSource; const ARequest: TSuperclassRequest;
      const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse; out APlan: TSuperclassPlan;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.TextChanges,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TEditingExtractSuperclassText = (ThereIsNoClassAt, HasNoFieldsMethodsOr, ConstructorsAndDestructorsStayStatements,
    IsNotAValidIdentifier, TheBaseClassMustNot, TheNameIsAlreadyTaken, MemberIsNotACandidate, CannotMove,
    PleaseSelectAtLeastOne, CannotBecomeAbstract, PleaseTakeItAlongOr, BecomesBecauseStillUsesIt,
    TheUnitHasNoImplementation, TheClassIsNoLonger);

const
  cTexts: array[TEditingExtractSuperclassText] of TAtlasText = (
    (De: 'An dieser Stelle steht keine Klasse.'; En: 'There is no class at this position.'),
    (De: '%s hat keine Felder, Methoden oder Properties für eine Basisklasse.';
     En: '%s has no fields, methods or properties for a base class.'),
    (De: 'Konstruktoren und Destruktoren bleiben; Anweisungen direkt bei inherited, die nur verschobene Felder ' +
      'setzen bzw. freigeben, wandern in einen eigenen der Basisklasse.';
     En: 'Constructors and destructors stay; statements right at inherited that only set or free moved fields go ' +
      'into an own one of the base class.'),
    (De: '"%s" ist kein gültiger Bezeichner.'; En: '"%s" is not a valid identifier.'),
    (De: 'Die Basisklasse darf nicht wie die Klasse heißen.';
     En: 'The base class must not have the same name as the class.'),
    (De: 'Der Name %s ist schon vergeben.'; En: 'The name %s is already taken.'),
    (De: 'Mitglied %d ist kein Kandidat.'; En: 'Member %d is not a candidate.'),
    (De: '%s kann nicht wandern: %s.'; En: '%s cannot move: %s.'),
    (De: 'Bitte mindestens ein Mitglied wählen.'; En: 'Please select at least one member.'),
    (De: '%s kann nicht abstrakt werden: %s.'; En: '%s cannot become abstract: %s.'),
    (De: '. Bitte mitnehmen oder abstrakt deklarieren.'; En: '. Please take it along or declare it abstract.'),
    (De: '%s wird %s, weil %s es weiter benutzt.'; En: '%s becomes %s because %s still uses it.'),
    (De: 'Die Unit hat keinen implementation-Teil für die Rümpfe der Basisklasse.';
     En: 'The unit has no implementation part for the bodies of the base class.'),
    (De: 'Die Klasse ist nach dem Umbau nicht mehr lesbar.';
     En: 'The class is no longer readable after the change.'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Aufteilung eines Konstruktors bzw. Destruktors.</summary>
  TStatementSplit = record
    Member: Integer;
    /// <summary>Oberste Anweisungen des Rumpfs, die wandern.</summary>
    Moved: TArray<TSyntaxNode>;
    /// <summary>Die inherited-Anweisung; nil ohne.</summary>
    Inherited_: TSyntaxNode;
    /// <summary>Namen, die die bleibenden Anweisungen benutzen.</summary>
    Remaining: TArray<string>;
  end;

  /// <summary>Namen für die Prüfung einer Anweisung: lokale, wandernde und bleibende.</summary>
  TSplitNames = record
    Locals: TArray<string>;
    Allowed: TArray<string>;
    Own: TArray<string>;
  end;

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function ContainsText(const AList: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
  begin
    if SameText(Item, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function StripT(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Wortteile eines Namens in CamelCase (PdfExport → Pdf, Export; HTMLView → HTML, View).</summary>
function Words(const AName: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 2 to Length(AName) do
  begin
    if CharInSet(AName[Index], ['A'..'Z']) and (CharInSet(AName[Index - 1], ['a'..'z', '0'..'9']) or
      ((Index < Length(AName)) and CharInSet(AName[Index + 1], ['a'..'z']) and
      CharInSet(AName[Index - 1], ['A'..'Z']))) then
    begin
      Result := Result + [Copy(AName, Start, Index - Start)];
      Start := Index;
    end;
  end;
  if Start <= Length(AName) then
  begin
    Result := Result + [Copy(AName, Start, MaxInt)];
  end;
end;

/// <summary>Namen, die ANode benutzt: Bezeichner und Self.X.</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
begin
  if ANode = nil then
  begin
    Exit;
  end;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    ANames := ANames + [ANode.Name];
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
  begin
    ANames := ANames + [ANode.Name];
  end;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    CollectNames(ANode[Index], ANames);
  end;
end;

function NamesOf(ANode: TSyntaxNode): TArray<string>;
begin
  Result := nil;
  CollectNames(ANode, Result);
end;

function HasInherited(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.InheritedExpr then
  begin
    Exit(True);
  end;
  // Nur der Aufruf selbst, nicht Argumente.
  if ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call] then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if HasInherited(ANode[Index]) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

procedure AddDeclaredNames(ASection: TSyntaxNode; var ANames: TArray<string>);
var
  mItem: Integer;
  mName: string;
begin
  for mItem := 0 to ASection.ChildCount - 1 do
  begin
    for mName in ASection[mItem].Name.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        ANames := ANames + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>Lokale Variablen und Konstanten einer Routine.</summary>
function LocalNames(ABody: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if ABody[mIndex].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
    begin
      AddDeclaredNames(ABody[mIndex], Result);
    end;
  end;
end;

/// <summary>Steht die Anweisung allein auf ihren Zeilen (davor nur Leerraum, dahinter höchstens ";")?</summary>
function WholeLines(ALayout: TClassLayout; ANode: TSyntaxNode): Boolean;
var
  First, Last: string;
begin
  First := ALayout.Lines[ANode.StartPos.Line];
  Last := ALayout.Lines[ANode.EndPos.Line];
  Result := (Trim(Copy(First, 1, ANode.StartPos.Character)) = '') and
    MatchText(Trim(Copy(Last, ANode.EndPos.Character + 1, MaxInt)), ['', ';']);
end;

function BlockOf(ABody: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ABody <> nil then
  begin
    Result := ABody.FindChild(TSyntaxKind.Block);
  end;
end;

/// <summary>Index der Anweisung mit inherited; -1 ohne.</summary>
function InheritedIndex(ABlock: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if HasInherited(ABlock[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Benutzt die Anweisung ein wanderndes Mitglied und weder lokale Variablen noch bleibende Mitglieder?
/// </summary>
function CanMove(const ANames: TArray<string>; const ACheck: TSplitNames): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if ContainsText(ACheck.Locals, mName) then
    begin
      Exit(False);
    end;
    if ContainsText(ACheck.Allowed, mName) then
    begin
      Result := True;
    end
    else if ContainsText(ACheck.Own, mName) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Konstruktor: zusammenhängend direkt hinter inherited; Destruktor: direkt davor (Reihenfolge bleibt).
/// </summary>
function ScanStart(AKind: TClassMemberKind; AInherit, ACount: Integer; out AStep: Integer): Integer;
begin
  if AKind = TClassMemberKind.Constructor_ then
  begin
    AStep := 1;
    Exit(AInherit + 1);
  end;
  AStep := -1;
  if AInherit < 0 then
  begin
    Result := ACount - 1;
  end
  else
  begin
    Result := AInherit - 1;
  end;
end;

/// <summary>Anweisungen ab AStart in Richtung AStep, die wandern können, in der Reihenfolge des Rumpfs.</summary>
function MovedStatements(ALayout: TClassLayout; ABlock: TSyntaxNode; AStart, AStep: Integer;
  const ACheck: TSplitNames): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mStatement: TSyntaxNode;
begin
  Result := nil;
  mIndex := AStart;
  while (mIndex >= 0) and (mIndex < ABlock.ChildCount) do
  begin
    mStatement := ABlock[mIndex];
    if not (WholeLines(ALayout, mStatement) and CanMove(NamesOf(mStatement), ACheck)) then
    begin
      Break;
    end;
    if AStep > 0 then
    begin
      Result := Result + [mStatement];
    end
    else
    begin
      Result := TArray<TSyntaxNode>.Create(mStatement) + Result;
    end;
    Inc(mIndex, AStep);
  end;
end;

function IsWithin(ANode: TSyntaxNode; const AMoved: TArray<TSyntaxNode>): Boolean;
begin
  Result := (AMoved <> nil) and (ANode.StartOffset >= AMoved[0].StartOffset) and
    (ANode.EndOffset <= AMoved[High(AMoved)].EndOffset);
end;

/// <summary>Namen, die die bleibenden Anweisungen benutzen.</summary>
function RemainingNames(ABlock: TSyntaxNode; const AMoved: TArray<TSyntaxNode>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ABlock.ChildCount - 1 do
  begin
    if not IsWithin(ABlock[mIndex], AMoved) then
    begin
      Result := Result + NamesOf(ABlock[mIndex]);
    end;
  end;
end;

/// <summary>Anweisungen von AMember (Konstruktor oder Destruktor), die in die Basisklasse wandern können.
/// </summary>
function SplitOf(ALayout: TClassLayout; AMember: Integer; const AAllowed, AOwn: TArray<string>;
  out ASplit: TStatementSplit): Boolean;
var
  mMember: TClassMember;
  mBlock: TSyntaxNode;
  mCheck: TSplitNames;
  mInherit, mStart, mStep: Integer;
begin
  ASplit := Default(TStatementSplit);
  ASplit.Member := AMember;
  mMember := ALayout.Members[AMember];
  mBlock := BlockOf(mMember.Body);
  // Der Destruktor der Basisklasse läuft nur über override.
  if (mBlock = nil) or (mMember.Kind = TClassMemberKind.Destructor_) and not mMember.HasDirective('override') then
  begin
    Exit(False);
  end;
  mCheck.Locals := LocalNames(mMember.Body);
  mCheck.Allowed := AAllowed;
  mCheck.Own := AOwn;
  mInherit := InheritedIndex(mBlock);
  if mInherit >= 0 then
  begin
    ASplit.Inherited_ := mBlock[mInherit];
  end;
  mStart := ScanStart(mMember.Kind, mInherit, mBlock.ChildCount, mStep);
  ASplit.Moved := MovedStatements(ALayout, mBlock, mStart, mStep, mCheck);
  ASplit.Remaining := RemainingNames(mBlock, ASplit.Moved);
  Result := ASplit.Moved <> nil;
end;

/// <summary>Zeilen AFirst..ALast der Anweisungen samt Umbruch.</summary>
function StatementLines(ALayout: TClassLayout; AFirst, ALast: TSyntaxNode): string;
begin
  Result := ALayout.LinesText(AFirst.StartPos.Line, ALast.EndPos.Line);
end;

/// <summary>Bereich der ganzen Zeilen AFirstLine..ALastLine samt Umbruch.</summary>
function LinesRange(AFirstLine, ALastLine: Integer): TTextRange;
begin
  Result := TTextRange.Create(AFirstLine, 0, ALastLine + 1, 0);
end;

/// <summary>Deklaration eines aufgeteilten Konstruktors bzw. Destruktors für oben (wie unten).</summary>
function SplitDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in TMemberTransfer.DirectiveTexts(ALayout, ALayout.Members[AIndex].Node) do
  begin
    Result := Result + ' ' + Directive + ';';
  end;
end;

/// <summary>Typparameter ohne Einschränkungen ("&lt;T: class; U&gt;" → "&lt;T, U&gt;"); '' ohne.</summary>
function GenericArgs(const AParams: string): string;
var
  Inner, Part, Name: string;
  Names: TArray<string>;
begin
  if AParams = '' then
  begin
    Exit('');
  end;
  Inner := Copy(AParams, 2, Length(AParams) - 2);
  Names := nil;
  for Part in Inner.Split([',', ';']) do
  begin
    Name := Trim(Part);
    if Pos(':', Name) > 0 then
    begin
      Name := Trim(Copy(Name, 1, Pos(':', Name) - 1));
    end;
    if IsIdentifier(Name) then
    begin
      Names := Names + [Name];
    end;
  end;
  Result := '<' + string.Join(', ', Names) + '>';
end;

/// <summary>Kopf eines Rumpfs mit ABaseName statt des Klassennamens.</summary>
function BodyHeader(ALayout: TClassLayout; AIndex: Integer; const ABaseName: string): string;
var
  Body, Header: TSyntaxNode;
  Text: string;
  Position: Integer;
begin
  Body := ALayout.Members[AIndex].Body;
  Header := Body.FindChild(TSyntaxKind.RoutineHeader);
  Text := Copy(ALayout.Text, Body.StartOffset + 1, Header.EndOffset - Body.StartOffset);
  if not Text.EndsWith(';') then
  begin
    Text := Text + ';';
  end;
  // Der erste Klassenname vor dem Punkt.
  Position := Pos(LowerCase(ALayout.Name) + '.', LowerCase(Text));
  if Position = 0 then
  begin
    Position := Pos(LowerCase(ALayout.Name) + '<', LowerCase(Text));
  end;
  if Position > 0 then
  begin
    Text := Copy(Text, 1, Position - 1) + ABaseName + Copy(Text, Position + Length(ALayout.Name), MaxInt);
  end;
  Result := Text;
end;

/// <summary>Ein aufgeteilter Konstruktor bzw. Destruktor benutzt AName nur noch, wenn die bleibenden Anweisungen
/// es tun.</summary>
function StaysUsed(const ASplits: TArray<TStatementSplit>; const AName: string): TStillUses;
begin
  Result :=
    function(AUser: Integer): Boolean
    var
      Split: TStatementSplit;
    begin
      Result := True;
      for Split in ASplits do
      begin
        if Split.Member = AUser then
        begin
          Result := ContainsText(Split.Remaining, AName);
        end;
      end;
    end;
end;

{ TExtractSuperclass }

class function TExtractSuperclass.SuggestName(const AClassName, ASuffix: string): string;
var
  Parts: TArray<string>;
  Rest: string;
begin
  Rest := StripT(AClassName);
  Parts := Words(Rest);
  if Length(Parts) > 1 then
  begin
    Rest := string.Join('', Copy(Parts, 1, MaxInt));
  end;
  if SameText(ASuffix, 'Custom') then
  begin
    Result := 'TCustom' + Rest;
  end
  else
  begin
    Result := 'T' + Rest + ASuffix;
  end;
end;

class function TExtractSuperclass.ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, False);
end;

/// <summary>Bisheriger Vorfahr ohne TObject; '' ohne.</summary>
function AncestorName(ALayout: TClassLayout): string;
begin
  Result := '';
  if (ALayout.Ancestors <> nil) and not SameText(ALayout.Ancestors[0], 'TObject') then
  begin
    Result := ALayout.Ancestors[0];
  end;
end;

function HasSplitMember(ALayout: TClassLayout): Boolean;
var
  mMember: TClassMember;
begin
  for mMember in ALayout.Members do
  begin
    if mMember.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name mit dem ganzen Klassennamen (TPdfExportBase bzw. TCustomPdfExport).</summary>
function FullName(const AClassName, ASuffix: string): string;
begin
  if SameText(ASuffix, 'Custom') then
  begin
    Result := 'TCustom' + StripT(AClassName);
  end
  else
  begin
    Result := 'T' + StripT(AClassName) + ASuffix;
  end;
end;

/// <summary>Erste freie Zahl ab 2 für AName (höchstens 100).</summary>
function FreeNumber(const AName: string; const ANameInUse: TNameInUse): Integer;
begin
  Result := 2;
  while ANameInUse(AName + IntToStr(Result)) and (Result < 100) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Vorschlag, der noch frei ist: kurz, dann mit dem ganzen Namen, dann mit Zahl.</summary>
function FreeName(const AClassName, ASuffix: string; const ANameInUse: TNameInUse): string;
begin
  Result := TExtractSuperclass.SuggestName(AClassName, ASuffix);
  if not (Assigned(ANameInUse) and ANameInUse(Result)) then
  begin
    Exit;
  end;
  Result := FullName(AClassName, ASuffix);
  if ANameInUse(Result) then
  begin
    Result := Result + IntToStr(FreeNumber(Result, ANameInUse));
  end;
end;

class function TExtractSuperclass.Prepare(const ASource: TClassSource; const ASuffix: string;
  const ANameInUse: TNameInUse; out AInfo: TSuperclassInfo; out AReason: string): Boolean;
var
  mDecl: TSyntaxNode;
  mLayout: TClassLayout;
  mSuffix: string;
begin
  AInfo := Default(TSuperclassInfo);
  AReason := '';
  mDecl := ClassAt(ASource.Tree, ASource.Line);
  if mDecl = nil then
  begin
    Exit(Fail(cTexts[TEditingExtractSuperclassText.ThereIsNoClassAt].Text, AReason));
  end;
  mLayout := TClassLayout.Read(ASource.Tree, ASource.Text, mDecl);
  try
    AInfo.ClassName := mLayout.Name;
    AInfo.Ancestor := AncestorName(mLayout);
    AInfo.Candidates := TMemberTransfer.Candidates(mLayout);
    if AInfo.Candidates = nil then
    begin
      AReason := cTexts[TEditingExtractSuperclassText.HasNoFieldsMethodsOr].Fmt([mLayout.Name]);
    end
    else
    begin
      mSuffix := ASuffix;
      if mSuffix = '' then
      begin
        mSuffix := 'Base';
      end;
      AInfo.SuggestedName := FreeName(mLayout.Name, mSuffix, ANameInUse);
      if HasSplitMember(mLayout) then
      begin
        AInfo.Notes := AInfo.Notes +
          [cTexts[TEditingExtractSuperclassText.ConstructorsAndDestructorsStayStatements].Text];
      end;
    end;
  finally
    mLayout.Free;
  end;
  Result := AReason = '';
end;


type
  /// <summary>Gewählte Mitglieder: alle, die verschobenen und die abstrakten.</summary>
  TSuperclassChoice = record
    Chosen: TArray<Integer>;
    Moved: TArray<Integer>;
    Abstracts: TArray<Integer>;
  end;

  TVisibilityLines = array[TClassVisibility] of TArray<string>;

  /// <summary>Baut aus Klasse und Auswahl den neuen Text der Unit samt Basisklasse.</summary>
  TSuperclassBuilder = class
  strict private
    FLayout: TClassLayout;
    FRequest: TSuperclassRequest;
    FChoice: TSuperclassChoice;
    FName: string;
    FLineBreak: string;
    FSplits: TArray<TStatementSplit>;
    FFinal: TArray<TClassVisibility>;
    FRelocate: TArray<Integer>;
    FAncestor: string;
    FHeaderOffset: Integer;
    procedure CollectSplits;
    procedure RaiseMember(AId: Integer; var APlan: TSuperclassPlan);
    procedure RaiseVisibilities(var APlan: TSuperclassPlan);
    function IsFieldMember(AIndex: Integer): Boolean;
    function DeclarationLines: TVisibilityLines;
    function BaseLines: TArray<string>;
    function BaseText(ATree: TSyntaxTree): string;
    function SplitBody(const ASplit: TStatementSplit): string;
    function Bodies(var APlan: TSuperclassPlan): TArray<string>;
    procedure FillNames(var APlan: TSuperclassPlan);
    function SplitEdits(const ASplit: TStatementSplit): TArray<TTextEdit>;
    function AncestorEdit: TTextEdit;
    function ClassEdits: TArray<TTextEdit>;
    function Relocated(var AText: string): Boolean;
    function AddBodies(ANext: TClassLayout; ATree: TSyntaxTree; const AText: string; const ABodies: TArray<string>;
      var AEdits: TArray<TTextEdit>): string;
    function Insert(const AText, ABaseText: string; const ABodies: TArray<string>; var APlan: TSuperclassPlan): string;
  public
    constructor Create(ALayout: TClassLayout; const ARequest: TSuperclassRequest; const AChoice: TSuperclassChoice);
    function Build(const ASource: TClassSource; const AIsInterface: TIsInterfaceType; var APlan: TSuperclassPlan;
      out AReason: string): Boolean;
  end;

function NameError(const AClassName, AName: string; const ANameInUse: TNameInUse): string;
begin
  Result := '';
  if not IsIdentifier(AName) then
  begin
    Result := cTexts[TEditingExtractSuperclassText.IsNotAValidIdentifier].Fmt([AName]);
  end
  else if SameText(AName, AClassName) then
  begin
    Result := cTexts[TEditingExtractSuperclassText.TheBaseClassMustNot].Text;
  end
  else if Assigned(ANameInUse) and ANameInUse(AName) then
  begin
    Result := cTexts[TEditingExtractSuperclassText.TheNameIsAlreadyTaken].Fmt([AName]);
  end;
end;

function CandidateError(const ACandidates: TArray<TTransferCandidate>; AId: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := TMemberTransfer.IndexOf(ACandidates, AId);
  if mIndex < 0 then
  begin
    Result := cTexts[TEditingExtractSuperclassText.MemberIsNotACandidate].Fmt([AId]);
  end
  else if not ACandidates[mIndex].Enabled then
  begin
    Result := cTexts[TEditingExtractSuperclassText.CannotMove].Fmt([ACandidates[mIndex].Name,
      ACandidates[mIndex].Reason]);
  end;
end;

function ChosenError(const ACandidates: TArray<TTransferCandidate>; const AMembers: TArray<Integer>;
  out AChosen: TArray<Integer>): string;
var
  mId: Integer;
begin
  AChosen := nil;
  if AMembers = nil then
  begin
    Exit(cTexts[TEditingExtractSuperclassText.PleaseSelectAtLeastOne].Text);
  end;
  for mId in AMembers do
  begin
    Result := CandidateError(ACandidates, mId);
    if Result <> '' then
    begin
      Exit;
    end;
    if not TMemberTransfer.Has(AChosen, mId) then
    begin
      AChosen := AChosen + [mId];
    end;
  end;
  Result := '';
end;

/// <summary>Teilt die Auswahl in verschobene und abstrakte Mitglieder; Fehler, wenn eines nicht abstrakt werden
/// kann.</summary>
function PartitionError(const ACandidates: TArray<TTransferCandidate>; const AAbstract: TArray<Integer>;
  var AChoice: TSuperclassChoice): string;
var
  mCandidate: TTransferCandidate;
begin
  AChoice.Moved := nil;
  AChoice.Abstracts := nil;
  for mCandidate in ACandidates do
  begin
    if not TMemberTransfer.Has(AChoice.Chosen, mCandidate.Id) then
    begin
      Continue;
    end;
    if not TMemberTransfer.Has(AAbstract, mCandidate.Id) then
    begin
      AChoice.Moved := AChoice.Moved + [mCandidate.Id];
    end
    else if mCandidate.CanAbstract then
    begin
      AChoice.Abstracts := AChoice.Abstracts + [mCandidate.Id];
    end
    else
    begin
      Exit(cTexts[TEditingExtractSuperclassText.CannotBecomeAbstract].Fmt([mCandidate.Name, mCandidate.Reason]));
    end;
  end;
  Result := '';
end;

function RequestError(const AInfo: TSuperclassInfo; const ARequest: TSuperclassRequest; const ANameInUse: TNameInUse;
  out AChoice: TSuperclassChoice): string;
begin
  AChoice := Default(TSuperclassChoice);
  Result := NameError(AInfo.ClassName, Trim(ARequest.Name), ANameInUse);
  if Result = '' then
  begin
    Result := ChosenError(AInfo.Candidates, ARequest.Members, AChoice.Chosen);
  end;
  if Result = '' then
  begin
    Result := PartitionError(AInfo.Candidates, ARequest.Abstract, AChoice);
  end;
end;

/// <summary>Was wandert, darf nur benutzen, was mitwandert (abstrakt zählt); '' wenn alles da ist.</summary>
function MissingError(ALayout: TClassLayout; const AChoice: TSuperclassChoice): string;
var
  mMissing: TArray<string>;
begin
  Result := '';
  mMissing := TMemberTransfer.MissingNeeds(ALayout, AChoice.Moved, AChoice.Chosen);
  if mMissing <> nil then
  begin
    Result := string.Join('; ', mMissing) + cTexts[TEditingExtractSuperclassText.PleaseTakeItAlongOr].Text;
  end;
end;

function IsSplitCandidate(const AMember: TClassMember): Boolean;
begin
  Result := (AMember.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_]) and
    not AMember.IsClassMember;
end;

/// <summary>Ist AName ein Interface? Ohne Prüfung nach der Namensregel IXxx.</summary>
function IsInterfaceName(const AName: string; const AIsInterface: TIsInterfaceType): Boolean;
begin
  if Assigned(AIsInterface) then
  begin
    Exit(AIsInterface(AName));
  end;
  Result := (Length(AName) > 1) and (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
end;

/// <summary>Vorfahr der Basisklasse: der bisherige ohne Interfaces und ohne TObject.</summary>
function BaseAncestor(ALayout: TClassLayout; const AIsInterface: TIsInterfaceType): string;
begin
  Result := AncestorName(ALayout);
  if (Result <> '') and IsInterfaceName(Result, AIsInterface) then
  begin
    Result := '';
  end;
end;

/// <summary>Kommt AName in den Zeilen als Wort vor?</summary>
function MentionsName(const ALines: TArray<string>; const AName: string): Boolean;
var
  mLine, mWord: string;
begin
  for mLine in ALines do
  begin
    for mWord in TArray<string>(mLine.Split([' ', '(', ')', ':', ';', ',', '<', '>', '[', ']', '.'])) do
    begin
      if SameText(mWord, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Steht vor der Klasse schon eine Vorwärtsdeklaration?</summary>
function DeclaredBefore(ATree: TSyntaxTree; ALayout: TClassLayout): Boolean;
var
  mFound: Boolean;
  mName: string;
  mLine: Integer;
begin
  mFound := False;
  mName := ALayout.Name;
  mLine := ALayout.HeaderLine;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, mName) and (ANode.StartPos.Line < mLine) then
      begin
        mFound := True;
      end;
    end);
  Result := mFound;
end;

function IsOverridable(const AMember: TClassMember): Boolean;
begin
  Result := AMember.HasDirective('virtual') or AMember.HasDirective('dynamic') or
    AMember.HasDirective('reintroduce');
end;

/// <summary>Kleinste Rumpfzeile der Klasse; -1 ohne Rümpfe.</summary>
function FirstBodyLine(ALayout: TClassLayout): Integer;
var
  mMember: TClassMember;
begin
  Result := -1;
  for mMember in ALayout.Members do
  begin
    if (mMember.Body <> nil) and ((Result < 0) or (mMember.BodyFirstLine < Result)) then
    begin
      Result := mMember.BodyFirstLine;
    end;
  end;
end;

{ TSuperclassBuilder }

constructor TSuperclassBuilder.Create(ALayout: TClassLayout; const ARequest: TSuperclassRequest;
  const AChoice: TSuperclassChoice);
begin
  inherited Create;
  FLayout := ALayout;
  FRequest := ARequest;
  FChoice := AChoice;
  FName := Trim(ARequest.Name);
  FLineBreak := ALayout.LineBreak;
end;

procedure TSuperclassBuilder.CollectSplits;
var
  mAllowed, mOwn: TArray<string>;
  mIndex: Integer;
  mSplit: TStatementSplit;
begin
  // Namen der Mitglieder: was oben steht (auch abstrakt) und was unten bleibt.
  mAllowed := nil;
  mOwn := nil;
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if TMemberTransfer.Has(FChoice.Chosen, mIndex) then
    begin
      mAllowed := mAllowed + [FLayout.Members[mIndex].Name];
    end
    else if FLayout.Members[mIndex].Kind <> TClassMemberKind.Other then
    begin
      mOwn := mOwn + [FLayout.Members[mIndex].Name];
    end;
  end;
  FSplits := nil;
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if IsSplitCandidate(FLayout.Members[mIndex]) and SplitOf(FLayout, mIndex, mAllowed, mOwn, mSplit) then
    begin
      FSplits := FSplits + [mSplit];
    end;
  end;
end;

procedure TSuperclassBuilder.RaiseMember(AId: Integer; var APlan: TSuperclassPlan);
var
  mName: string;
begin
  mName := FLayout.Members[AId].Name;
  FFinal[AId] := FRequest.RaiseVisibility;
  APlan.Raised := APlan.Raised + [mName];
  APlan.Warnings := APlan.Warnings + [cTexts[TEditingExtractSuperclassText.BecomesBecauseStillUsesIt].Fmt([mName,
    TClassEdits.VisibilityName(FRequest.RaiseVisibility), FLayout.Name])];
  // Die Überschreibung unten braucht dieselbe Sichtbarkeit (sonst H2269).
  if TMemberTransfer.Has(FChoice.Abstracts, AId) then
  begin
    FRelocate := FRelocate + [AId];
  end;
end;

procedure TSuperclassBuilder.RaiseVisibilities(var APlan: TSuperclassPlan);
var
  mIndex, mId: Integer;
begin
  SetLength(FFinal, Length(FLayout.Members));
  for mIndex := 0 to High(FLayout.Members) do
  begin
    FFinal[mIndex] := FLayout.Members[mIndex].Visibility;
  end;
  FRelocate := nil;
  for mId in FChoice.Chosen do
  begin
    if TMemberTransfer.MustRaise(FLayout, mId, FChoice.Moved, TMemberTransfer.Has(FChoice.Abstracts, mId),
      FRequest.SameUnit, StaysUsed(FSplits, FLayout.Members[mId].Name)) then
    begin
      RaiseMember(mId, APlan);
    end;
  end;
end;

function TSuperclassBuilder.IsFieldMember(AIndex: Integer): Boolean;
begin
  Result := FLayout.Members[AIndex].Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar];
end;

function TSuperclassBuilder.DeclarationLines: TVisibilityLines;
var
  mVisibility: TClassVisibility;
  mIndex: Integer;
  mSplit: TStatementSplit;
begin
  // Je Abschnitt Felder vor Methoden und Properties.
  for mVisibility := Low(TClassVisibility) to High(TClassVisibility) do
  begin
    Result[mVisibility] := nil;
  end;
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if TMemberTransfer.Has(FChoice.Moved, mIndex) and IsFieldMember(mIndex) then
    begin
      Result[FFinal[mIndex]] := Result[FFinal[mIndex]] + TMemberTransfer.MemberLines(FLayout, mIndex);
    end;
  end;
  for mSplit in FSplits do
  begin
    mVisibility := FLayout.Members[mSplit.Member].Visibility;
    Result[mVisibility] := Result[mVisibility] + [FLayout.MemberIndent + SplitDeclaration(FLayout, mSplit.Member)];
  end;
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if TMemberTransfer.Has(FChoice.Abstracts, mIndex) then
    begin
      Result[FFinal[mIndex]] := Result[FFinal[mIndex]] +
        [FLayout.MemberIndent + TMemberTransfer.AbstractDeclaration(FLayout, mIndex)];
    end
    else if TMemberTransfer.Has(FChoice.Moved, mIndex) and not IsFieldMember(mIndex) then
    begin
      Result[FFinal[mIndex]] := Result[FFinal[mIndex]] + TMemberTransfer.MemberLines(FLayout, mIndex);
    end;
  end;
end;

function TSuperclassBuilder.BaseLines: TArray<string>;
var
  mHeader: string;
  mLines: TVisibilityLines;
  mVisibility: TClassVisibility;
begin
  mLines := DeclarationLines;
  mHeader := FLayout.Indent + FName + FLayout.GenericParams + ' = class';
  if FAncestor <> '' then
  begin
    mHeader := mHeader + '(' + FAncestor + ')';
  end;
  Result := TArray<string>.Create(mHeader);
  for mVisibility := Low(TClassVisibility) to High(TClassVisibility) do
  begin
    if mLines[mVisibility] <> nil then
    begin
      Result := Result + [FLayout.Indent + TClassEdits.VisibilityName(mVisibility)] + mLines[mVisibility];
    end;
  end;
  Result := Result + [FLayout.Indent + 'end;'];
end;

function TSuperclassBuilder.BaseText(ATree: TSyntaxTree): string;
var
  mLines: TArray<string>;
begin
  mLines := BaseLines;
  // In derselben Unit trennt eine Leerzeile die Klassen; für eine neue Unit wandert die Basisklasse gleich
  // weiter, ohne eine Leerzeile zurückzulassen.
  Result := string.Join(FLineBreak, mLines) + FLineBreak;
  if FRequest.SameUnit then
  begin
    Result := Result + FLineBreak;
  end;
  // Braucht oben jemand die Klasse selbst, steht vorher eine Vorwärtsdeklaration.
  FHeaderOffset := 0;
  if MentionsName(mLines, FLayout.Name) and not DeclaredBefore(ATree, FLayout) then
  begin
    Result := FLayout.Indent + FLayout.Name + FLayout.GenericParams + ' = class;' + FLineBreak + FLineBreak + Result;
    FHeaderOffset := 2;
  end;
end;

function TSuperclassBuilder.SplitBody(const ASplit: TStatementSplit): string;
var
  mMember: TClassMember;
  mIndent: string;
begin
  mMember := FLayout.Members[ASplit.Member];
  mIndent := TTextLines.IndentOf(FLayout.Lines[BlockOf(mMember.Body).StartPos.Line]);
  Result := BodyHeader(FLayout, ASplit.Member, FName) + FLineBreak + mIndent + 'begin' + FLineBreak;
  if (mMember.Kind = TClassMemberKind.Constructor_) and (ASplit.Inherited_ <> nil) then
  begin
    Result := Result + StatementLines(FLayout, ASplit.Inherited_, ASplit.Inherited_);
  end;
  Result := Result + StatementLines(FLayout, ASplit.Moved[0], ASplit.Moved[High(ASplit.Moved)]);
  if (mMember.Kind = TClassMemberKind.Destructor_) and (ASplit.Inherited_ <> nil) then
  begin
    Result := Result + StatementLines(FLayout, ASplit.Inherited_, ASplit.Inherited_);
  end;
  Result := Result + mIndent + 'end;';
end;

function TSuperclassBuilder.Bodies(var APlan: TSuperclassPlan): TArray<string>;
var
  mSplit: TStatementSplit;
  mIndex: Integer;
begin
  Result := nil;
  for mSplit in FSplits do
  begin
    Result := Result + [SplitBody(mSplit)];
    APlan.Split := APlan.Split + [FLayout.Members[mSplit.Member].Name];
  end;
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if TMemberTransfer.Has(FChoice.Moved, mIndex) and (FLayout.Members[mIndex].Body <> nil) then
    begin
      Result := Result + [TClassEdits.BodyText(FLayout, mIndex, FName)];
    end;
  end;
end;

procedure TSuperclassBuilder.FillNames(var APlan: TSuperclassPlan);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if TMemberTransfer.Has(FChoice.Moved, mIndex) then
    begin
      APlan.Moved := APlan.Moved + [FLayout.Members[mIndex].Name];
    end
    else if TMemberTransfer.Has(FChoice.Abstracts, mIndex) then
    begin
      APlan.Abstracts := APlan.Abstracts + [FLayout.Members[mIndex].Name];
    end;
  end;
end;

function TSuperclassBuilder.SplitEdits(const ASplit: TStatementSplit): TArray<TTextEdit>;
var
  mMember: TClassMember;
  mStatement: string;
begin
  Result := nil;
  mMember := FLayout.Members[ASplit.Member];
  // Oben steht er wie bisher; unten überschreibt er ihn (virtual) bzw. verdeckt ihn ohne reintroduce.
  if IsOverridable(mMember) then
  begin
    Result := TMemberTransfer.OverrideEdits(FLayout, mMember.Node, False);
  end;
  mStatement := '';
  if ASplit.Inherited_ = nil then
  begin
    // Ohne inherited ruft die Klasse den neuen Konstruktor bzw. Destruktor an der Stelle auf.
    mStatement := TTextLines.IndentOf(FLayout.Lines[ASplit.Moved[0].StartPos.Line]) + 'inherited;' + FLineBreak;
  end
  else if (mMember.Kind <> TClassMemberKind.Destructor_) and
    not SameText(Trim(StatementLines(FLayout, ASplit.Inherited_, ASplit.Inherited_)), 'inherited;') then
  begin
    Result := Result + [TTextEdit.Create(LinesRange(ASplit.Inherited_.StartPos.Line, ASplit.Inherited_.EndPos.Line),
      TTextLines.IndentOf(FLayout.Lines[ASplit.Inherited_.StartPos.Line]) + 'inherited;' + FLineBreak)];
  end;
  Result := Result + [TTextEdit.Create(LinesRange(ASplit.Moved[0].StartPos.Line,
    ASplit.Moved[High(ASplit.Moved)].EndPos.Line), mStatement)];
end;

function TSuperclassBuilder.AncestorEdit: TTextEdit;
var
  mAncestors: TArray<string>;
  mIndex: Integer;
begin
  mAncestors := TArray<string>.Create(FName + GenericArgs(FLayout.GenericParams));
  for mIndex := 0 to High(FLayout.Ancestors) do
  begin
    if (mIndex > 0) or (FAncestor = '') and not SameText(FLayout.Ancestors[0], 'TObject') then
    begin
      mAncestors := mAncestors + [FLayout.Ancestors[mIndex]];
    end;
  end;
  Result := TClassEdits.SetAncestors(FLayout, mAncestors);
end;

function TSuperclassBuilder.ClassEdits: TArray<TTextEdit>;
var
  mId: Integer;
  mSplit: TStatementSplit;
begin
  // Abschnitte, deren Mitglieder alle wandern, fallen weg.
  Result := TClassEdits.DeleteMembers(FLayout, FChoice.Moved, True) +
    TMemberTransfer.EmptiedSections(FLayout, FChoice.Moved);
  for mId in FChoice.Abstracts do
  begin
    Result := Result + TMemberTransfer.OverrideEdits(FLayout, FLayout.Members[mId].Node, True);
  end;
  for mSplit in FSplits do
  begin
    Result := Result + SplitEdits(mSplit);
  end;
  Result := Result + [AncestorEdit];
end;

function TSuperclassBuilder.Relocated(var AText: string): Boolean;
var
  mOlds: TArray<TClassMember>;
  mId: Integer;
begin
  mOlds := nil;
  for mId in FRelocate do
  begin
    mOlds := mOlds + [FLayout.Members[mId]];
  end;
  Result := TMemberTransfer.Relocate(AText, FLayout.Name, mOlds, FRequest.RaiseVisibility);
end;

function TSuperclassBuilder.AddBodies(ANext: TClassLayout; ATree: TSyntaxTree; const AText: string;
  const ABodies: TArray<string>; var AEdits: TArray<TTextEdit>): string;
var
  mFirst, mLine: Integer;
begin
  Result := '';
  mFirst := FirstBodyLine(ANext);
  if mFirst >= 0 then
  begin
    AEdits := AEdits + [TClassEdits.InsertBeforeLine(mFirst, string.Join(FLineBreak + FLineBreak, ABodies) +
      FLineBreak + FLineBreak)];
    Exit;
  end;
  mLine := TClassEdits.BodiesEnd(ATree, FLayout.Name);
  if mLine < 0 then
  begin
    Result := cTexts[TEditingExtractSuperclassText.TheUnitHasNoImplementation].Text;
  end
  else
  begin
    AEdits := AEdits + [TClassEdits.InsertBodies(AText, mLine, ABodies)];
  end;
end;

function TSuperclassBuilder.Insert(const AText, ABaseText: string; const ABodies: TArray<string>;
  var APlan: TSuperclassPlan): string;
var
  mNext: TClassLayout;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mNext := TMemberTransfer.ParseLayout(AText, FLayout.Name, mTree);
  if mNext = nil then
  begin
    Exit(cTexts[TEditingExtractSuperclassText.TheClassIsNoLonger].Text);
  end;
  try
    mEdits := [TClassEdits.InsertBeforeLine(mNext.FirstLine, ABaseText)];
    APlan.BaseLine := mNext.FirstLine + FHeaderOffset;
    Result := '';
    if ABodies <> nil then
    begin
      Result := AddBodies(mNext, mTree, AText, ABodies, mEdits);
    end;
    if Result = '' then
    begin
      APlan.Text := TTextChanges.Apply(AText, mEdits);
    end;
  finally
    mNext.Free;
    mTree.Free;
  end;
end;

function TSuperclassBuilder.Build(const ASource: TClassSource; const AIsInterface: TIsInterfaceType;
  var APlan: TSuperclassPlan; out AReason: string): Boolean;
var
  mText, mBase: string;
  mBodies: TArray<string>;
begin
  APlan.ClassName := FLayout.Name;
  APlan.BaseName := FName;
  CollectSplits;
  RaiseVisibilities(APlan);
  FAncestor := BaseAncestor(FLayout, AIsInterface);
  mBase := BaseText(ASource.Tree);
  mBodies := Bodies(APlan);
  FillNames(APlan);
  // Schritt 1: Klasse ändern; Schritt 2: gehobene abstrakte Methoden unten in den Abschnitt der neuen
  // Sichtbarkeit; Schritt 3: Basisklasse über die Klasse, ihre Rümpfe vor die der Klasse.
  mText := TTextChanges.Apply(ASource.Text, ClassEdits);
  if Relocated(mText) then
  begin
    AReason := Insert(mText, mBase, mBodies, APlan);
  end
  else
  begin
    AReason := cTexts[TEditingExtractSuperclassText.TheClassIsNoLonger].Text;
  end;
  Result := AReason = '';
end;

class function TExtractSuperclass.Plan(const ASource: TClassSource; const ARequest: TSuperclassRequest;
  const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse; out APlan: TSuperclassPlan;
  out AReason: string): Boolean;
var
  mInfo: TSuperclassInfo;
  mChoice: TSuperclassChoice;
  mLayout: TClassLayout;
  mBuilder: TSuperclassBuilder;
begin
  APlan := Default(TSuperclassPlan);
  if not Prepare(ASource, 'Base', nil, mInfo, AReason) then
  begin
    Exit(False);
  end;
  AReason := RequestError(mInfo, ARequest, ANameInUse, mChoice);
  if AReason <> '' then
  begin
    Exit(False);
  end;
  mLayout := TClassLayout.Read(ASource.Tree, ASource.Text, ClassAt(ASource.Tree, ASource.Line));
  try
    AReason := MissingError(mLayout, mChoice);
    Result := AReason = '';
    if Result then
    begin
      mBuilder := TSuperclassBuilder.Create(mLayout, ARequest, mChoice);
      try
        Result := mBuilder.Build(ASource, AIsInterface, APlan, AReason);
      finally
        mBuilder.Free;
      end;
    end;
  finally
    mLayout.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.ExtractSuperclass', cTexts);

end.
