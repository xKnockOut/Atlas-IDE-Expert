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
  Atlas.Common.Editing.ExtractInterface;

type
  {$SCOPEDENUMS ON}
  TSuperclassMemberKind = (Field, Method, Property_);
  {$SCOPEDENUMS OFF}

  /// <summary>Ist AName ein Interface (für den ersten Eintrag der Vorfahrenliste)?</summary>
  TIsInterfaceType = reference to function(const AName: string): Boolean;

  TSuperclassCandidate = record
    /// <summary>Index des Mitglieds in TClassLayout.Members.</summary>
    Id: Integer;
    Name: string;
    Kind: TSuperclassMemberKind;
    /// <summary>Deklaration bzw. Kopf ohne Direktiven.</summary>
    Display: string;
    Visibility: TClassVisibility;
    Enabled: Boolean;
    /// <summary>Warum nicht wählbar bzw. warum nicht abstrakt; '' sonst.</summary>
    Reason: string;
    /// <summary>Methode, die oben abstrakt deklariert werden kann.</summary>
    CanAbstract: Boolean;
    /// <summary>Ids der Mitglieder, die dieses Mitglied in Deklaration und Rumpf benutzt.</summary>
    Needs: TArray<Integer>;
  end;

  TSuperclassInfo = record
    ClassName: string;
    SuggestedName: string;
    /// <summary>Bisheriger Vorfahr (ohne Interfaces); '' ohne.</summary>
    Ancestor: string;
    Candidates: TArray<TSuperclassCandidate>;
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
    class function Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer; const ASuffix: string;
      const ANameInUse: TNameInUse; out AInfo: TSuperclassInfo; out AReason: string): Boolean; static;
    /// <summary>Neuer Text der Unit für ARequest; False mit Grund (Name, Auswahl, Abhängigkeiten).</summary>
    class function Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const ARequest: TSuperclassRequest; const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse;
      out APlan: TSuperclassPlan; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TextChanges;

const
  /// <summary>Direktiven, die eine abstrakte Deklaration oben behält.</summary>
  KeptDirectives: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');
  HintDirectives: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');

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

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

function Contains(const AList: TArray<Integer>; AValue: Integer): Boolean;
var
  Item: Integer;
begin
  for Item in AList do
    if Item = AValue then
      Exit(True);
  Result := False;
end;

function AllIn(const AItems, AList: TArray<Integer>): Boolean;
var
  Item: Integer;
begin
  for Item in AItems do
    if not Contains(AList, Item) then
      Exit(False);
  Result := True;
end;

function ContainsText(const AList: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AValue) then
      Exit(True);
  Result := False;
end;

function StripT(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
    Result := Copy(Result, 2, MaxInt);
end;

/// <summary>Wortteile eines Namens in CamelCase (PdfExport → Pdf, Export; HTMLView → HTML, View).</summary>
function Words(const AName: string): TArray<string>;
var
  Index, Start: Integer;
begin
  Result := nil;
  Start := 1;
  for Index := 2 to Length(AName) do
    if CharInSet(AName[Index], ['A'..'Z']) and (CharInSet(AName[Index - 1], ['a'..'z', '0'..'9']) or
      ((Index < Length(AName)) and CharInSet(AName[Index + 1], ['a'..'z']) and
      CharInSet(AName[Index - 1], ['A'..'Z']))) then
    begin
      Result := Result + [Copy(AName, Start, Index - Start)];
      Start := Index;
    end;
  if Start <= Length(AName) then
    Result := Result + [Copy(AName, Start, MaxInt)];
end;

/// <summary>Kandidat für Basisklassen: Feld, Klassenvariable, Methode oder Property.</summary>
function KindOf(const AMember: TClassMember; out AKind: TSuperclassMemberKind): Boolean;
begin
  Result := True;
  case AMember.Kind of
    TClassMemberKind.Field, TClassMemberKind.ClassVar:
      AKind := TSuperclassMemberKind.Field;
    TClassMemberKind.Method:
      AKind := TSuperclassMemberKind.Method;
    TClassMemberKind.Property_:
      AKind := TSuperclassMemberKind.Property_;
  else
    Result := False;
  end;
end;

/// <summary>Warum eine Methode oben nicht abstrakt werden kann; '' wenn doch.</summary>
function AbstractBlocker(const AMember: TClassMember): string;
begin
  if AMember.Kind <> TClassMemberKind.Method then
    Exit('nur Methoden');
  if AMember.IsGeneric then
    Exit('generische Methoden können nicht virtuell sein');
  if AMember.HasDirective('static') then
    Exit('statische Klassenmethoden können nicht virtuell sein');
  if AMember.HasDirective('message') then
    Exit('Message-Methoden bleiben, wie sie sind');
  if AMember.HasDirective('override') then
    Exit('überschreibt schon eine Methode des Vorfahren');
  if AMember.IsAbstract then
    Exit('ist schon abstrakt');
  Result := '';
end;

/// <summary>Namen, die ANode benutzt: Bezeichner und Self.X.</summary>
procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Index: Integer;
begin
  if ANode = nil then
    Exit;
  if ANode.Kind = TSyntaxKind.Identifier then
    ANames := ANames + [ANode.Name]
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    ANames := ANames + [ANode.Name];
  for Index := 0 to ANode.ChildCount - 1 do
    CollectNames(ANode[Index], ANames);
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
    Exit(True);
  // Nur der Aufruf selbst, nicht Argumente.
  if ANode.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.Call] then
    for Index := 0 to ANode.ChildCount - 1 do
      if HasInherited(ANode[Index]) then
        Exit(True);
  Result := False;
end;

/// <summary>Lokale Variablen und Konstanten einer Routine.</summary>
function LocalNames(ABody: TSyntaxNode): TArray<string>;
var
  Index, Item: Integer;
  Name: string;
begin
  Result := nil;
  for Index := 0 to ABody.ChildCount - 1 do
    if ABody[Index].Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection] then
      for Item := 0 to ABody[Index].ChildCount - 1 do
        for Name in ABody[Index][Item].Name.Split([',']) do
          if Trim(Name) <> '' then
            Result := Result + [Trim(Name)];
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
    Result := ABody.FindChild(TSyntaxKind.Block);
end;

/// <summary>Anweisungen von AMember (Konstruktor oder Destruktor), die in die Basisklasse wandern können.
/// </summary>
function SplitOf(ALayout: TClassLayout; AMember: Integer; const AAllowed, AOwn: TArray<string>;
  out ASplit: TStatementSplit): Boolean;
var
  Member: TClassMember;
  Block: TSyntaxNode;
  Locals, Names: TArray<string>;
  Index, Inherit, Step: Integer;
  Statement: TSyntaxNode;
  Name: string;
  UsesMoved, Blocked: Boolean;
begin
  ASplit := Default(TStatementSplit);
  ASplit.Member := AMember;
  Member := ALayout.Members[AMember];
  Block := BlockOf(Member.Body);
  if Block = nil then
    Exit(False);
  // Der Destruktor der Basisklasse läuft nur über override.
  if (Member.Kind = TClassMemberKind.Destructor_) and not Member.HasDirective('override') then
    Exit(False);
  Locals := LocalNames(Member.Body);
  Inherit := -1;
  for Index := 0 to Block.ChildCount - 1 do
    if HasInherited(Block[Index]) then
    begin
      Inherit := Index;
      Break;
    end;
  if Inherit >= 0 then
    ASplit.Inherited_ := Block[Inherit];
  // Konstruktor: zusammenhängend direkt hinter inherited; Destruktor: direkt davor (Reihenfolge bleibt).
  if Member.Kind = TClassMemberKind.Constructor_ then
  begin
    Index := Inherit + 1;
    Step := 1;
  end
  else
  begin
    Index := Inherit - 1;
    if Inherit < 0 then
      Index := Block.ChildCount - 1;
    Step := -1;
  end;
  while (Index >= 0) and (Index < Block.ChildCount) do
  begin
    Statement := Block[Index];
    if not WholeLines(ALayout, Statement) then
      Break;
    Names := NamesOf(Statement);
    UsesMoved := False;
    Blocked := False;
    for Name in Names do
      if ContainsText(Locals, Name) then
        Blocked := True
      else if ContainsText(AAllowed, Name) then
        UsesMoved := True
      else if ContainsText(AOwn, Name) then
        Blocked := True;
    if Blocked or not UsesMoved then
      Break;
    if Step > 0 then
      ASplit.Moved := ASplit.Moved + [Statement]
    else
      ASplit.Moved := [Statement] + ASplit.Moved;
    Inc(Index, Step);
  end;
  for Index := 0 to Block.ChildCount - 1 do
    if not ((ASplit.Moved <> nil) and (Block[Index].StartOffset >= ASplit.Moved[0].StartOffset) and
      (Block[Index].EndOffset <= ASplit.Moved[High(ASplit.Moved)].EndOffset)) then
      ASplit.Remaining := ASplit.Remaining + NamesOf(Block[Index]);
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

/// <summary>Direktiven des Kopfs AHeader als Text in Reihenfolge.</summary>
function DirectiveTexts(ALayout: TClassLayout; AHeader: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AHeader.ChildCount - 1 do
    if AHeader[Index].Kind = TSyntaxKind.Directive then
      Result := Result + [CollapseSpace(ALayout.TextOf(AHeader[Index]))];
end;

/// <summary>Änderungen, die aus dem Kopf AHeader eine überschreibende Methode machen: virtual/dynamic →
/// override, reintroduce und abstract weg; ohne virtual mit AAddOverride override vor den Hinweisdirektiven bzw.
/// am Ende.</summary>
function OverrideEdits(ALayout: TClassLayout; AHeader: TSyntaxNode; AAddOverride: Boolean): TArray<TTextEdit>;
var
  Index, Offset: Integer;
  Directive: TSyntaxNode;
  Found: Boolean;
  Lines: TLineTable;
  HintPos: TTextPosition;
  HasHint: Boolean;
begin
  Result := nil;
  Found := False;
  HasHint := False;
  HintPos := AHeader.EndPos;
  Lines := TLineTable.Build(ALayout.Text);
  for Index := 0 to AHeader.ChildCount - 1 do
  begin
    Directive := AHeader[Index];
    if Directive.Kind <> TSyntaxKind.Directive then
      Continue;
    if MatchText(Directive.Name, ['virtual', 'dynamic']) and not Found then
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(Directive.StartPos, Directive.EndPos), 'override')];
      Found := True;
    end
    else if MatchText(Directive.Name, ['reintroduce', 'abstract', 'virtual', 'dynamic']) then
    begin
      // "; reintroduce" samt Semikolon davor entfernen.
      Offset := Directive.StartOffset;
      while (Offset > 0) and CharInSet(ALayout.Text[Offset], [' ', #9, #13, #10]) do
        Dec(Offset);
      if (Offset > 0) and (ALayout.Text[Offset] = ';') then
        Dec(Offset);
      Result := Result + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(Offset), Directive.EndPos), '')];
    end
    else if MatchText(Directive.Name, HintDirectives) and not HasHint then
    begin
      HasHint := True;
      HintPos := Directive.StartPos;
    end;
  end;
  if Found or not AAddOverride then
    Exit;
  if HasHint then
    Result := Result + [TTextEdit.Create(TTextRange.Create(HintPos, HintPos), 'override; ')]
  else
    Result := Result + [TTextEdit.Create(TTextRange.Create(AHeader.EndPos, AHeader.EndPos), ' override;')];
end;

/// <summary>Abstrakte Deklaration für oben: Kopf, behaltene Direktiven, virtual; abstract;.</summary>
function AbstractDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  // reintroduce bleibt: Die Basisklasse verdeckt dann die Methode des alten Vorfahren (sonst W1010).
  if ALayout.Members[AIndex].HasDirective('reintroduce') then
    Result := Result + ' reintroduce;';
  for Directive in ALayout.Members[AIndex].Directives do
    if MatchText(Directive, KeptDirectives) then
      Result := Result + ' ' + Directive + ';';
  Result := Result + ' virtual; abstract;';
end;

/// <summary>Deklaration eines aufgeteilten Konstruktors bzw. Destruktors für oben (wie unten).</summary>
function SplitDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in DirectiveTexts(ALayout, ALayout.Members[AIndex].Node) do
    Result := Result + ' ' + Directive + ';';
end;

/// <summary>Deklarationszeilen eines Mitglieds für oben (samt Doku und Attributen, Einrückung wie in der
/// Klasse); eine Feldgruppe nur mit dem einen Namen.</summary>
function MemberLines(ALayout: TClassLayout; AIndex: Integer): TArray<string>;
var
  Member: TClassMember;
  Line: Integer;
  Doc: string;
begin
  Result := nil;
  Member := ALayout.Members[AIndex];
  if Member.IsFieldGroup then
  begin
    for Doc in ALayout.DocLines(AIndex) do
      Result := Result + [ALayout.MemberIndent + Doc];
    Result := Result + [ALayout.MemberIndent + ALayout.Declaration(AIndex)];
    Exit;
  end;
  for Line := Member.FirstLine to Member.LastLine do
    Result := Result + [ALayout.Lines[Line]];
  // Aus einem class-var-Abschnitt: oben ohne den Abschnitt, also mit class var davor.
  if (Member.Kind = TClassMemberKind.ClassVar) and not StartsText('class', TrimLeft(Result[High(Result)])) then
    Result[High(Result)] := ALayout.MemberIndent + 'class var ' + TrimLeft(Result[High(Result)]);
end;

/// <summary>Typparameter ohne Einschränkungen ("&lt;T: class; U&gt;" → "&lt;T, U&gt;"); '' ohne.</summary>
function GenericArgs(const AParams: string): string;
var
  Inner, Part, Name: string;
  Names: TArray<string>;
begin
  if AParams = '' then
    Exit('');
  Inner := Copy(AParams, 2, Length(AParams) - 2);
  Names := nil;
  for Part in Inner.Split([',', ';']) do
  begin
    Name := Trim(Part);
    if Pos(':', Name) > 0 then
      Name := Trim(Copy(Name, 1, Pos(':', Name) - 1));
    if IsIdentifier(Name) then
      Names := Names + [Name];
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
    Text := Text + ';';
  // Der erste Klassenname vor dem Punkt.
  Position := Pos(LowerCase(ALayout.Name) + '.', LowerCase(Text));
  if Position = 0 then
    Position := Pos(LowerCase(ALayout.Name) + '<', LowerCase(Text));
  if Position > 0 then
    Text := Copy(Text, 1, Position - 1) + ABaseName + Copy(Text, Position + Length(ALayout.Name), MaxInt);
  Result := Text;
end;

/// <summary>Benutzt Code außerhalb der Klasse und ihrer Rümpfe AName als ".AName"?</summary>
function UsedOutside(ALayout: TClassLayout; const AName: string): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index, Previous, Line: Integer;
  Member: TClassMember;
  Inside: Boolean;
begin
  Tokens := ALayout.Tree.Tokens;
  for Index := 1 to High(Tokens) do
  begin
    if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not SameText(Tokens[Index].Text, AName) then
      Continue;
    Previous := Index - 1;
    while (Previous >= 0) and (Tokens[Previous].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
      Dec(Previous);
    if (Previous < 0) or not Tokens[Previous].IsSymbol('.') then
      Continue;
    Line := Tokens[Index].StartPos.Line;
    Inside := (Line >= ALayout.FirstLine) and (Line <= ALayout.EndLine);
    for Member in ALayout.Members do
      if (Member.Body <> nil) and (Line >= Member.BodyFirstLine) and (Line <= Member.BodyLastLine) then
        Inside := True;
    if not Inside then
      Exit(True);
  end;
  Result := False;
end;

/// <summary>Mitglied in ALayout, das dem Mitglied AOld (aus einem früheren Stand) entspricht: Name, Art und
/// Parametertypen; -1 ohne.</summary>
function Same(ALayout: TClassLayout; const AOld: TClassMember): Integer;
var
  Index: Integer;
begin
  for Index in ALayout.Find(AOld.Name) do
    if (ALayout.Members[Index].Kind = AOld.Kind) and
      (string.Join(',', ALayout.Members[Index].ParameterTypes) = string.Join(',', AOld.ParameterTypes)) then
      Exit(Index);
  Result := -1;
end;

function ParseLayout(const AText, AName: string; out ATree: TSyntaxTree): TClassLayout;
var
  Decl: TSyntaxNode;
begin
  ATree := TPascalParser.Parse(AText);
  Decl := TClassLayout.DeclNamed(ATree, AName);
  if Decl = nil then
  begin
    FreeAndNil(ATree);
    Exit(nil);
  end;
  Result := TClassLayout.Read(ATree, AText, Decl);
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
    Rest := string.Join('', Copy(Parts, 1, MaxInt));
  if SameText(ASuffix, 'Custom') then
    Result := 'TCustom' + Rest
  else
    Result := 'T' + Rest + ASuffix;
end;

class function TExtractSuperclass.ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, False);
end;

class function TExtractSuperclass.Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ASuffix: string; const ANameInUse: TNameInUse; out AInfo: TSuperclassInfo; out AReason: string): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Index, Need, Counter: Integer;
  Member: TClassMember;
  Item: TSuperclassCandidate;
  Kind: TSuperclassMemberKind;
  Name, Suffix: string;
  HasSplit: Boolean;
begin
  AInfo := Default(TSuperclassInfo);
  AReason := '';
  Decl := ClassAt(ATree, ALine);
  if Decl = nil then
    Exit(Fail('An dieser Stelle steht keine Klasse.', AReason));
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AInfo.ClassName := Layout.Name;
    if (Layout.Ancestors <> nil) and not SameText(Layout.Ancestors[0], 'TObject') then
      AInfo.Ancestor := Layout.Ancestors[0];
    HasSplit := False;
    for Index := 0 to High(Layout.Members) do
    begin
      Member := Layout.Members[Index];
      if Member.Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_] then
        HasSplit := True;
      if not KindOf(Member, Kind) then
        Continue;
      Item := Default(TSuperclassCandidate);
      Item.Id := Index;
      Item.Name := Member.Name;
      Item.Kind := Kind;
      Item.Visibility := Member.Visibility;
      Item.Enabled := True;
      if Kind = TSuperclassMemberKind.Method then
        Item.Display := Layout.Head(Index)
      else
        Item.Display := Layout.Declaration(Index);
      if Member.IsRedeclaration then
      begin
        Item.Enabled := False;
        Item.Reason := 'ändert nur die Sichtbarkeit eines geerbten Mitglieds';
      end
      else if Kind = TSuperclassMemberKind.Method then
      begin
        Item.Reason := AbstractBlocker(Member);
        Item.CanAbstract := Item.Reason = '';
      end;
      for Need in Layout.UsedBy(Index) do
        if KindOf(Layout.Members[Need], Kind) then
          Item.Needs := Item.Needs + [Need];
      AInfo.Candidates := AInfo.Candidates + [Item];
    end;
    if AInfo.Candidates = nil then
      Exit(Fail(Format('%s hat keine Felder, Methoden oder Properties für eine Basisklasse.', [Layout.Name]),
        AReason));
    Suffix := ASuffix;
    if Suffix = '' then
      Suffix := 'Base';
    Name := SuggestName(Layout.Name, Suffix);
    if Assigned(ANameInUse) and ANameInUse(Name) then
    begin
      // Mit dem ganzen Namen (TPdfExportBase), dann mit Zahl.
      if SameText(Suffix, 'Custom') then
        Name := 'TCustom' + StripT(Layout.Name)
      else
        Name := 'T' + StripT(Layout.Name) + Suffix;
      if ANameInUse(Name) then
      begin
        Counter := 2;
        while ANameInUse(Name + IntToStr(Counter)) and (Counter < 100) do
          Inc(Counter);
        Name := Name + IntToStr(Counter);
      end;
    end;
    AInfo.SuggestedName := Name;
    if HasSplit then
      AInfo.Notes := AInfo.Notes + ['Konstruktoren und Destruktoren bleiben; Anweisungen direkt bei inherited, die ' +
        'nur verschobene Felder setzen bzw. freigeben, wandern in einen eigenen der Basisklasse.'];
  finally
    Layout.Free;
  end;
  Result := True;
end;

class function TExtractSuperclass.Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ARequest: TSuperclassRequest; const AIsInterface: TIsInterfaceType; const ANameInUse: TNameInUse;
  out APlan: TSuperclassPlan; out AReason: string): Boolean;
var
  Layout, Next: TClassLayout;
  Tree: TSyntaxTree;
  Info: TSuperclassInfo;
  Candidate: TSuperclassCandidate;
  Id, Index, Need, Line, FirstBody: Integer;
  Member: TClassMember;
  Moved, Abstracts, Chosen, Relocate: TArray<Integer>;
  Missing, AllowedNames, OwnNames, BaseLines, Bodies, Ancestors, Declarations: TArray<string>;
  Visibilities: array[TClassVisibility] of TArray<string>;
  FinalVisibility: array of TClassVisibility;
  Splits: TArray<TStatementSplit>;
  Split: TStatementSplit;
  Edits: TArray<TTextEdit>;
  Visibility: TClassVisibility;
  Used, ForwardNeeded: Boolean;
  LineBreak, Indent, Text, Header, Body, Name, Ancestor, BaseText, Statement: string;
  User, HeaderOffset: Integer;
begin
  APlan := Default(TSuperclassPlan);
  AReason := '';
  if not Prepare(ATree, AText, ALine, 'Base', nil, Info, AReason) then
    Exit(False);
  Name := Trim(ARequest.Name);
  if not IsIdentifier(Name) then
    Exit(Fail(Format('"%s" ist kein gültiger Bezeichner.', [Name]), AReason));
  if SameText(Name, Info.ClassName) then
    Exit(Fail('Die Basisklasse darf nicht wie die Klasse heißen.', AReason));
  if Assigned(ANameInUse) and ANameInUse(Name) then
    Exit(Fail(Format('Der Name %s ist schon vergeben.', [Name]), AReason));
  if ARequest.Members = nil then
    Exit(Fail('Bitte mindestens ein Mitglied wählen.', AReason));
  Chosen := nil;
  for Id in ARequest.Members do
  begin
    Index := -1;
    for Need := 0 to High(Info.Candidates) do
      if Info.Candidates[Need].Id = Id then
        Index := Need;
    if Index < 0 then
      Exit(Fail(Format('Mitglied %d ist kein Kandidat.', [Id]), AReason));
    if not Info.Candidates[Index].Enabled then
      Exit(Fail(Format('%s kann nicht wandern: %s.', [Info.Candidates[Index].Name, Info.Candidates[Index].Reason]),
        AReason));
    if not Contains(Chosen, Id) then
      Chosen := Chosen + [Id];
  end;
  Moved := nil;
  Abstracts := nil;
  for Candidate in Info.Candidates do
  begin
    if not Contains(Chosen, Candidate.Id) then
      Continue;
    if Contains(ARequest.Abstract, Candidate.Id) then
    begin
      if not Candidate.CanAbstract then
        Exit(Fail(Format('%s kann nicht abstrakt werden: %s.', [Candidate.Name, Candidate.Reason]), AReason));
      Abstracts := Abstracts + [Candidate.Id];
    end
    else
      Moved := Moved + [Candidate.Id];
  end;
  Layout := TClassLayout.Read(ATree, AText, ClassAt(ATree, ALine));
  try
    // Was wandert, darf nur benutzen, was mitwandert (abstrakt zählt).
    Missing := nil;
    for Id in Moved do
      for Need in Layout.UsedBy(Id) do
        if Contains(Chosen, Need) or not (Layout.Members[Need].Kind in [TClassMemberKind.Field,
          TClassMemberKind.ClassVar, TClassMemberKind.Method, TClassMemberKind.Property_]) then
          Continue
        else
        begin
          Text := Format('%s braucht %s', [Layout.Members[Id].Name, Layout.Members[Need].Name]);
          if not ContainsText(Missing, Text) then
            Missing := Missing + [Text];
        end;
    if Missing <> nil then
      Exit(Fail(string.Join('; ', Missing) + '. Bitte mitnehmen oder abstrakt deklarieren.', AReason));
    LineBreak := Layout.LineBreak;
    APlan.ClassName := Layout.Name;
    APlan.BaseName := Name;
    // Namen der Mitglieder: was oben steht (auch abstrakt) und was unten bleibt.
    AllowedNames := nil;
    OwnNames := nil;
    for Index := 0 to High(Layout.Members) do
      if Contains(Chosen, Index) then
        AllowedNames := AllowedNames + [Layout.Members[Index].Name]
      else if Layout.Members[Index].Kind <> TClassMemberKind.Other then
        OwnNames := OwnNames + [Layout.Members[Index].Name];
    // Konstruktoren und Destruktoren aufteilen.
    Splits := nil;
    for Index := 0 to High(Layout.Members) do
      if (Layout.Members[Index].Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_]) and
        not Layout.Members[Index].IsClassMember and SplitOf(Layout, Index, AllowedNames, OwnNames, Split) then
        Splits := Splits + [Split];
    // Sichtbarkeit oben.
    FinalVisibility := nil;
    SetLength(FinalVisibility, Length(Layout.Members));
    for Index := 0 to High(Layout.Members) do
      FinalVisibility[Index] := Layout.Members[Index].Visibility;
    Relocate := nil;
    for Id in Chosen do
    begin
      Member := Layout.Members[Id];
      if not (Member.Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_]) then
        Continue;
      if (Member.Visibility = TClassVisibility.Private_) and ARequest.SameUnit then
        Continue;
      Used := Contains(Abstracts, Id);
      if not Used then
        for User in Layout.UsersOf(Id) do
        begin
          if Contains(Moved, User) then
            Continue;
          if Layout.Members[User].Kind in [TClassMemberKind.Constructor_, TClassMemberKind.Destructor_] then
          begin
            Used := True;
            for Split in Splits do
              if Split.Member = User then
                Used := ContainsText(Split.Remaining, Member.Name);
          end
          else
            Used := True;
          if Used then
            Break;
        end;
      if not Used and (Member.Visibility = TClassVisibility.Private_) then
        Used := UsedOutside(Layout, Member.Name);
      if not Used then
        Continue;
      FinalVisibility[Id] := ARequest.RaiseVisibility;
      APlan.Raised := APlan.Raised + [Member.Name];
      APlan.Warnings := APlan.Warnings + [Format('%s wird %s, weil %s es weiter benutzt.', [Member.Name,
        TClassEdits.VisibilityName(ARequest.RaiseVisibility), Layout.Name])];
      // Die Überschreibung unten braucht dieselbe Sichtbarkeit (sonst H2269).
      if Contains(Abstracts, Id) then
        Relocate := Relocate + [Id];
    end;
    // Deklarationen oben, je Abschnitt Felder vor Methoden und Properties.
    for Visibility := Low(TClassVisibility) to High(TClassVisibility) do
      Visibilities[Visibility] := nil;
    for Index := 0 to High(Layout.Members) do
      if Contains(Moved, Index) and (Layout.Members[Index].Kind in [TClassMemberKind.Field,
        TClassMemberKind.ClassVar]) then
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] + MemberLines(Layout, Index);
    for Split in Splits do
      Visibilities[Layout.Members[Split.Member].Visibility] := Visibilities[Layout.Members[Split.Member].Visibility] +
        [Layout.MemberIndent + SplitDeclaration(Layout, Split.Member)];
    for Index := 0 to High(Layout.Members) do
      if Contains(Abstracts, Index) then
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] +
          [Layout.MemberIndent + AbstractDeclaration(Layout, Index)]
      else if Contains(Moved, Index) and not (Layout.Members[Index].Kind in [TClassMemberKind.Field,
        TClassMemberKind.ClassVar]) then
        Visibilities[FinalVisibility[Index]] := Visibilities[FinalVisibility[Index]] + MemberLines(Layout, Index);
    Indent := Layout.Indent;
    Ancestor := '';
    if (Layout.Ancestors <> nil) and not SameText(Layout.Ancestors[0], 'TObject') then
    begin
      Ancestor := Layout.Ancestors[0];
      if Assigned(AIsInterface) and AIsInterface(Ancestor) then
        Ancestor := ''
      else if not Assigned(AIsInterface) and (Length(Ancestor) > 1) and (Ancestor[1] = 'I') and
        CharInSet(Ancestor[2], ['A'..'Z']) then
        Ancestor := '';
    end;
    BaseLines := nil;
    Header := Indent + Name + Layout.GenericParams + ' = class';
    if Ancestor <> '' then
      Header := Header + '(' + Ancestor + ')';
    BaseLines := BaseLines + [Header];
    for Visibility := Low(TClassVisibility) to High(TClassVisibility) do
      if Visibilities[Visibility] <> nil then
        BaseLines := BaseLines + [Indent + TClassEdits.VisibilityName(Visibility)] + Visibilities[Visibility];
    BaseLines := BaseLines + [Indent + 'end;'];
    // In derselben Unit trennt eine Leerzeile die Klassen; für eine neue Unit wandert die Basisklasse gleich
    // weiter, ohne eine Leerzeile zurückzulassen.
    BaseText := string.Join(LineBreak, BaseLines) + LineBreak;
    if ARequest.SameUnit then
      BaseText := BaseText + LineBreak;
    // Braucht oben jemand die Klasse selbst, steht vorher eine Vorwärtsdeklaration.
    ForwardNeeded := False;
    HeaderOffset := 0;
    for Text in BaseLines do
      for Statement in TArray<string>(Text.Split([' ', '(', ')', ':', ';', ',', '<', '>', '[', ']', '.'])) do
        if SameText(Statement, Layout.Name) then
          ForwardNeeded := True;
    if ForwardNeeded then
    begin
      ATree.Root.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          Result := True;
          if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, Layout.Name) and
            (ANode.StartPos.Line < Layout.HeaderLine) then
            ForwardNeeded := False;
        end);
      if ForwardNeeded then
      begin
        BaseText := Indent + Layout.Name + Layout.GenericParams + ' = class;' + LineBreak + LineBreak + BaseText;
        HeaderOffset := 2;
      end;
    end;
    // Rümpfe oben.
    Bodies := nil;
    for Split in Splits do
    begin
      Member := Layout.Members[Split.Member];
      Body := BodyHeader(Layout, Split.Member, Name) + LineBreak +
        TTextLines.IndentOf(Layout.Lines[BlockOf(Member.Body).StartPos.Line]) + 'begin' + LineBreak;
      if (Member.Kind = TClassMemberKind.Constructor_) and (Split.Inherited_ <> nil) then
        Body := Body + StatementLines(Layout, Split.Inherited_, Split.Inherited_);
      Body := Body + StatementLines(Layout, Split.Moved[0], Split.Moved[High(Split.Moved)]);
      if (Member.Kind = TClassMemberKind.Destructor_) and (Split.Inherited_ <> nil) then
        Body := Body + StatementLines(Layout, Split.Inherited_, Split.Inherited_);
      Body := Body + TTextLines.IndentOf(Layout.Lines[BlockOf(Member.Body).StartPos.Line]) + 'end;';
      Bodies := Bodies + [Body];
      APlan.Split := APlan.Split + [Member.Name];
    end;
    for Index := 0 to High(Layout.Members) do
      if Contains(Moved, Index) and (Layout.Members[Index].Body <> nil) then
        Bodies := Bodies + [TClassEdits.BodyText(Layout, Index, Name)];
    for Index := 0 to High(Layout.Members) do
      if Contains(Moved, Index) then
        APlan.Moved := APlan.Moved + [Layout.Members[Index].Name]
      else if Contains(Abstracts, Index) then
        APlan.Abstracts := APlan.Abstracts + [Layout.Members[Index].Name];
    // Schritt 1: Klasse ändern; Abschnitte, deren Mitglieder alle wandern, fallen weg.
    Edits := TClassEdits.DeleteMembers(Layout, Moved, True);
    for Index := 0 to High(Layout.Sections) do
      if (Layout.Sections[Index].HeadLine >= 0) and (Layout.Sections[Index].Members <> nil) and
        AllIn(Layout.Sections[Index].Members, Moved) then
        Edits := Edits + [TTextEdit.Create(LinesRange(Layout.Sections[Index].HeadLine,
          Layout.Sections[Index].HeadLine), '')];
    for Id in Abstracts do
      Edits := Edits + OverrideEdits(Layout, Layout.Members[Id].Node, True);
    for Split in Splits do
    begin
      Member := Layout.Members[Split.Member];
      // Oben steht er wie bisher; unten überschreibt er ihn (virtual) bzw. verdeckt ihn ohne reintroduce.
      if Member.HasDirective('virtual') or Member.HasDirective('dynamic') or Member.HasDirective('reintroduce') then
        Edits := Edits + OverrideEdits(Layout, Member.Node, False);
      Statement := '';
      if (Split.Inherited_ = nil) or (Member.Kind = TClassMemberKind.Destructor_) then
      begin
        // Ohne inherited ruft die Klasse den neuen Konstruktor bzw. Destruktor an der Stelle auf.
        if Split.Inherited_ = nil then
          Statement := TTextLines.IndentOf(Layout.Lines[Split.Moved[0].StartPos.Line]) + 'inherited;' + LineBreak;
      end
      else if not SameText(Trim(StatementLines(Layout, Split.Inherited_, Split.Inherited_)), 'inherited;') then
        Edits := Edits + [TTextEdit.Create(LinesRange(Split.Inherited_.StartPos.Line, Split.Inherited_.EndPos.Line),
          TTextLines.IndentOf(Layout.Lines[Split.Inherited_.StartPos.Line]) + 'inherited;' + LineBreak)];
      Edits := Edits + [TTextEdit.Create(LinesRange(Split.Moved[0].StartPos.Line,
        Split.Moved[High(Split.Moved)].EndPos.Line), Statement)];
    end;
    Ancestors := [Name + GenericArgs(Layout.GenericParams)];
    for Index := 0 to High(Layout.Ancestors) do
      if (Index > 0) or (Ancestor = '') and not SameText(Layout.Ancestors[0], 'TObject') then
        Ancestors := Ancestors + [Layout.Ancestors[Index]];
    Edits := Edits + [TClassEdits.SetAncestors(Layout, Ancestors)];
    Text := TTextChanges.Apply(AText, Edits);
    // Schritt 2: gehobene abstrakte Methoden unten in den Abschnitt der neuen Sichtbarkeit.
    if Relocate <> nil then
    begin
      Next := ParseLayout(Text, Layout.Name, Tree);
      if Next = nil then
        Exit(Fail('Die Klasse ist nach dem Umbau nicht mehr lesbar.', AReason));
      try
        Edits := nil;
        Declarations := nil;
        Chosen := nil;
        for Id in Relocate do
        begin
          Index := Same(Next, Layout.Members[Id]);
          if Index < 0 then
            Continue;
          Chosen := Chosen + [Index];
          Edits := Edits + TClassEdits.DeleteMember(Next, Index, False);
          Statement := '';
          for Line := Next.Members[Index].FirstLine to Next.Members[Index].LastLine do
          begin
            if Statement <> '' then
              Statement := Statement + #10;
            Statement := Statement + Trim(Next.Lines[Line]);
          end;
          Declarations := Declarations + [Statement];
        end;
        for Index := 0 to High(Next.Sections) do
          if (Next.Sections[Index].HeadLine >= 0) and (Next.Sections[Index].Members <> nil) and
            AllIn(Next.Sections[Index].Members, Chosen) then
            Edits := Edits + [TTextEdit.Create(LinesRange(Next.Sections[Index].HeadLine,
              Next.Sections[Index].HeadLine), '')];
        if Declarations <> nil then
          Edits := Edits + [TClassEdits.InsertMembers(Next, ARequest.RaiseVisibility, False, Declarations)];
        Text := TTextChanges.Apply(Text, Edits);
      finally
        Next.Free;
        Tree.Free;
      end;
    end;
    // Schritt 3: Basisklasse über die Klasse, ihre Rümpfe vor die der Klasse.
    Next := ParseLayout(Text, Layout.Name, Tree);
    if Next = nil then
      Exit(Fail('Die Klasse ist nach dem Umbau nicht mehr lesbar.', AReason));
    try
      Edits := [TClassEdits.InsertBeforeLine(Text, Next.FirstLine, BaseText)];
      APlan.BaseLine := Next.FirstLine + HeaderOffset;
      if Bodies <> nil then
      begin
        FirstBody := -1;
        for Member in Next.Members do
          if (Member.Body <> nil) and ((FirstBody < 0) or (Member.BodyFirstLine < FirstBody)) then
            FirstBody := Member.BodyFirstLine;
        if FirstBody >= 0 then
          Edits := Edits + [TClassEdits.InsertBeforeLine(Text, FirstBody, string.Join(LineBreak + LineBreak, Bodies) +
            LineBreak + LineBreak)]
        else
        begin
          Line := TClassEdits.BodiesEnd(Tree, Text, Layout.Name);
          if Line < 0 then
            Exit(Fail('Die Unit hat keinen implementation-Teil für die Rümpfe der Basisklasse.', AReason));
          Edits := Edits + [TClassEdits.InsertBodies(Text, Line, Bodies)];
        end;
      end;
      APlan.Text := TTextChanges.Apply(Text, Edits);
    finally
      Next.Free;
      Tree.Free;
    end;
  finally
    Layout.Free;
  end;
  Result := True;
end;

end.
