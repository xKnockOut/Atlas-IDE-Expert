unit Atlas.Common.Editing.ClassLayout;

// Gemeinsamer Baustein der Umbauten über mehrere Klassen (#664 Interface
// herauslösen, #713 Basisklasse herauslösen, #675 Mitglied verschieben, #717
// Zugriffsmethode durch Feld ersetzen, #716 Sicher löschen): liest eine
// Klassendeklaration samt Rümpfen der Unit und erzeugt die Änderungen, die
// alle diese Umbauten brauchen.
//
// Lesen (TClassLayout.Read):
//   - Kopf: Name, Typparameter, Vorfahrenliste mit Bereich, Zeilen (samt
//     Doku-Kommentar und Attributen darüber), Einrückung, Zeile des end.
//   - Mitglieder mit Art, Sichtbarkeit (strict eingeschlossen), Direktiven,
//     Typ, Parametern, read/write einer Property, Zeilen der Deklaration samt
//     Doku-Kommentar (///) und Attributen direkt darüber und dem Rumpf in der
//     implementation. Felder einer Gruppe („FA, FB: Integer“) sind je ein
//     Mitglied mit derselben Deklaration. Überladene Methoden finden ihren
//     Rumpf über die Parametertypen.
//   - Abschnitte (private … published) mit ihren Mitgliedern.
//   - Verwendung: welche Mitglieder ein Mitglied in Deklaration und Rumpf
//     benutzt (Bezeichner ohne Punkt davor oder mit Self.), und welche
//     Mitglieder es benutzen.
//
// Ändern (TClassEdits): Mitglied samt Rumpf löschen (eine Feldgruppe behält
// die übrigen Namen), Deklarationen in einen Abschnitt einfügen (Felder vor
// die Methoden des Abschnitts, sonst ans Ende; ohne passenden Abschnitt ein
// neuer vor end), Vorfahrenliste ersetzen, Rumpf mit anderem Klassennamen
// kopieren und Rümpfe hinter die letzte Methode einer Klasse setzen.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree;

type
  {$SCOPEDENUMS ON}
  /// <summary>Sichtbarkeit eines Klassenabschnitts, aufsteigend.</summary>
  TClassVisibility = (StrictPrivate, Private_, StrictProtected, Protected_, Public_, Published_);
  TClassMemberKind = (Field, ClassVar, Method, Constructor_, Destructor_, Property_, Other);
  {$SCOPEDENUMS OFF}

  TClassMember = record
    Kind: TClassMemberKind;
    Name: string;
    /// <summary>Alle Namen der Felddeklaration ("FA, FB: Integer" → FA, FB); sonst nur Name.</summary>
    GroupNames: TArray<string>;
    /// <summary>Field, VarDecl, RoutineHeader, PropertyDecl oder der Knoten eines anderen Mitglieds.</summary>
    Node: TSyntaxNode;
    Visibility: TClassVisibility;
    /// <summary>class procedure, class function, class var, class property, class constructor.</summary>
    IsClassMember: Boolean;
    /// <summary>Direktiven in Kleinschreibung (virtual, overload, …).</summary>
    Directives: TArray<string>;
    /// <summary>Methode mit eigenen Typparametern.</summary>
    IsGeneric: Boolean;
    /// <summary>Erste Zeile samt Doku-Kommentar und Attributen direkt darüber, letzte Zeile der Deklaration.
    /// </summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>Erste Zeile des Doku-Kommentars (///) direkt über der Deklaration bzw. ihren Attributen; -1 ohne.
    /// </summary>
    DocLine: Integer;
    /// <summary>Typ des Felds bzw. der Property, Ergebnistyp einer Funktion; '' ohne.</summary>
    TypeName: string;
    /// <summary>Parameter ohne Klammern, Leerraum zusammengefasst; bei Properties die Indexparameter.</summary>
    Parameters: string;
    /// <summary>Typen der Parameter in Reihenfolge (je Name einer Gruppe einer).</summary>
    ParameterTypes: TArray<string>;
    /// <summary>Property: Namen hinter read, write, index und stored; '' ohne.</summary>
    ReadAccessor: string;
    WriteAccessor: string;
    IndexSpecifier: string;
    StoredSpecifier: string;
    /// <summary>Property mit "default;" hinter dem Semikolon (Standard-Array-Property).</summary>
    IsDefaultArray: Boolean;
    /// <summary>Property ohne Typ, die nur die Sichtbarkeit eines geerbten Mitglieds ändert.</summary>
    IsRedeclaration: Boolean;
    /// <summary>Implementierung in der Datei; nil ohne (abstrakt, extern, nicht gefunden).</summary>
    Body: TSyntaxNode;
    /// <summary>Zeilen des Rumpfs samt Doku-Kommentar darüber; -1 ohne Rumpf.</summary>
    BodyFirstLine: Integer;
    BodyLastLine: Integer;
    function IsMethod: Boolean;
    function IsFunction: Boolean;
    function HasDirective(const AName: string): Boolean;
    /// <summary>virtual, dynamic, override oder abstract.</summary>
    function IsVirtual: Boolean;
    function IsAbstract: Boolean;
    function IsFieldGroup: Boolean;
  end;

  TClassSection = record
    Visibility: TClassVisibility;
    /// <summary>Zeile des Schlüsselworts; -1 beim ersten Abschnitt ohne Schlüsselwort.</summary>
    HeadLine: Integer;
    /// <summary>Indizes in TClassLayout.Members.</summary>
    Members: TArray<Integer>;
  end;

  TClassLayout = class
  private
    FText: string;
    FTree: TSyntaxTree;
    FLines: TArray<string>;
    procedure ReadHeader;
    procedure ReadMembers;
    procedure FindBodies;
    function DocStart(ALine: Integer): Integer;
    function NodeText(ANode: TSyntaxNode): string;
    function TokenRange(AFirstOffset, ALastOffset: Integer; out AFirst, ALast: Integer): Boolean;
    function AfterClass(AOffset: Integer): Boolean;
  public
    Decl: TSyntaxNode;
    ClassNode: TSyntaxNode;
    Name: string;
    /// <summary>Typparameter samt spitzen Klammern ("&lt;T&gt;"); '' ohne.</summary>
    GenericParams: string;
    /// <summary>Einträge der Vorfahrenliste in Reihenfolge (Text ohne Leerraum am Rand).</summary>
    Ancestors: TArray<string>;
    /// <summary>Offsets der Klammern der Vorfahrenliste; -1 ohne Liste.</summary>
    HeritageOpen: Integer;
    HeritageClose: Integer;
    /// <summary>Offset hinter "class" bzw. "class abstract"/"class sealed": dort beginnt eine neue Liste.</summary>
    HeritageInsert: Integer;
    /// <summary>Erste Zeile samt Doku-Kommentar und Attributen, Kopfzeile, Zeile des end.</summary>
    FirstLine: Integer;
    HeaderLine: Integer;
    EndLine: Integer;
    /// <summary>Einrückung der Kopfzeile und der Mitglieder.</summary>
    Indent: string;
    MemberIndent: string;
    LineBreak: string;
    /// <summary>Die Klasse steht im interface-Teil.</summary>
    InInterface: Boolean;
    Members: TArray<TClassMember>;
    Sections: TArray<TClassSection>;
    /// <summary>Liest ADecl (TypeDecl mit ClassType); der Aufrufer gibt das Objekt frei. ATree und AText müssen
    /// so lange leben wie das Objekt.</summary>
    class function Read(ATree: TSyntaxTree; const AText: string; ADecl: TSyntaxNode): TClassLayout; static;
    /// <summary>Klassendeklaration, deren Kopfzeile ALine ist; mit AInside auch jede Zeile bis zum end. nil ohne.
    /// </summary>
    class function DeclAt(ATree: TSyntaxTree; ALine: Integer; AInside: Boolean): TSyntaxNode; static;
    /// <summary>Klassendeklaration mit dem Namen AName (ohne Typparameter); nil ohne.</summary>
    class function DeclNamed(ATree: TSyntaxTree; const AName: string): TSyntaxNode; static;
    /// <summary>Alle Klassendeklarationen der Datei (ohne Vorwärtsdeklarationen und Kurzformen ohne Rumpf).
    /// </summary>
    class function AllDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>; static;
    /// <summary>Indizes der Mitglieder mit dem Namen AName.</summary>
    function Find(const AName: string): TArray<Integer>;
    /// <summary>Mitglied, dessen Deklaration ALine enthält (Doku-Kommentar eingeschlossen); -1 ohne.</summary>
    function MemberAtLine(ALine: Integer): Integer;
    /// <summary>Mitglieder, die AIndex in Deklaration (Property-Zugriff) und Rumpf benutzt, ohne AIndex selbst.
    /// </summary>
    function UsedBy(AIndex: Integer): TArray<Integer>;
    /// <summary>Mitglieder, die AIndex in Deklaration oder Rumpf benutzen, ohne AIndex selbst.</summary>
    function UsersOf(AIndex: Integer): TArray<Integer>;
    /// <summary>Text eines Knotens.</summary>
    function TextOf(ANode: TSyntaxNode): string;
    /// <summary>Deklaration von AIndex als eine Zeile ohne Einrückung und ohne Doku ("function Foo: Integer;
    /// virtual;"); bei einer Feldgruppe nur der eine Name ("FA: Integer;").</summary>
    function Declaration(AIndex: Integer): string;
    /// <summary>Zeilen des Doku-Kommentars von AIndex ohne Einrückung; leer ohne.</summary>
    function DocLines(AIndex: Integer): TArray<string>;
    /// <summary>Kopf ohne Direktiven ("function Foo(const A: Integer): string;"), Leerraum zusammengefasst.
    /// </summary>
    function Head(AIndex: Integer): string;
    /// <summary>Text der Zeilen AFirst..ALast samt Umbrüchen.</summary>
    function LinesText(AFirst, ALast: Integer): string;
    property Text: string read FText;
    property Tree: TSyntaxTree read FTree;
    property Lines: TArray<string> read FLines;
  end;

  TClassEdits = class
  public
    /// <summary>Name eines Abschnitts: strict private, private, …</summary>
    class function VisibilityName(AVisibility: TClassVisibility): string; static;
    /// <summary>Aus dem Wort eines Abschnitts ("strict protected"); Public_ bei Unbekanntem.</summary>
    class function VisibilityOf(const AName: string): TClassVisibility; static;
    /// <summary>Zeilen AFirst..ALast samt Umbruch löschen; dazu eine Leerzeile dahinter, wenn auch davor eine
    /// steht.</summary>
    class function DeleteLines(ALayout: TClassLayout; AFirst, ALast: Integer): TTextEdit; static;
    /// <summary>Deklaration von AIndex löschen (Feldgruppe: nur diesen Namen). Mit ABody auch den Rumpf.
    /// </summary>
    class function DeleteMember(ALayout: TClassLayout; AIndex: Integer; ABody: Boolean): TArray<TTextEdit>;
      static;
    /// <summary>Mehrere Mitglieder löschen; Namen derselben Feldgruppe werden zusammengefasst.</summary>
    class function DeleteMembers(ALayout: TClassLayout; const AIndexes: TArray<Integer>;
      ABodies: Boolean): TArray<TTextEdit>; static;
    /// <summary>ADeclarations (ohne Einrückung, je Eintrag eine oder mehrere Zeilen mit #10) in den Abschnitt
    /// AVisibility von ALayout einfügen. Felder (AFields) kommen vor die erste Methode bzw. Property des letzten
    /// solchen Abschnitts, sonst ans Ende des letzten solchen Abschnitts; ohne einen ein neuer Abschnitt vor dem
    /// ersten Abschnitt höherer Sichtbarkeit bzw. vor end.</summary>
    class function InsertMembers(ALayout: TClassLayout; AVisibility: TClassVisibility; AFields: Boolean;
      const ADeclarations: TArray<string>): TTextEdit; static;
    /// <summary>Vorfahrenliste durch AAncestors ersetzen (leer: Liste entfernen).</summary>
    class function SetAncestors(ALayout: TClassLayout; const AAncestors: TArray<string>): TTextEdit; static;
    /// <summary>Rumpf von AIndex (samt Doku-Kommentar) mit AClassName statt des Klassennamens im Kopf; '' ohne
    /// Rumpf. Zeilenenden wie die Unit, ohne Umbruch am Ende.</summary>
    class function BodyText(ALayout: TClassLayout; AIndex: Integer; const AClassName: string): string; static;
    /// <summary>Zeile, hinter der Rümpfe der Klasse AClassName in ATree stehen: Ende des letzten Rumpfs der
    /// Klasse, sonst Ende der implementation-Deklarationen (vor initialization bzw. end.); -1 ohne
    /// implementation.</summary>
    class function BodiesEnd(ATree: TSyntaxTree; const AText, AClassName: string): Integer; static;
    /// <summary>Rümpfe ABodies (je ein Text, ohne Umbruch am Ende) hinter Zeile ALine einfügen, je durch eine
    /// Leerzeile getrennt.</summary>
    class function InsertBodies(const AText: string; ALine: Integer; const ABodies: TArray<string>): TTextEdit;
      static;
    /// <summary>Den Namen hinter AKeyword (read, write) der Property AIndex durch ANewName ersetzen; False ohne
    /// diesen Spezifizierer.</summary>
    class function ReplaceAccessor(ALayout: TClassLayout; AIndex: Integer; const AKeyword, ANewName: string;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Text am Anfang der Zeile ALine einfügen.</summary>
    class function InsertBeforeLine(const AText: string; ALine: Integer; const ANewText: string): TTextEdit;
      static;
  end;

/// <summary>Leerraum zusammenfassen und am Rand entfernen.</summary>
function CollapseSpace(const AText: string): string;
/// <summary>Bezeichner nach Delphi-Regeln (Buchstabe oder _, danach auch Ziffern, optional &amp; davor).
/// </summary>
function IsIdentifier(const AName: string): Boolean;
/// <summary>Kommentar oder Compiler-Direktive.</summary>
function IsTrivia(const AToken: TPascalToken): Boolean;
/// <summary>Index des ersten Tokens ab AOffset; Length(ATokens) dahinter.</summary>
function TokenIndexAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Character,
  Atlas.Text.Lines;

const
  VirtualDirectives: array[0..3] of string = ('virtual', 'dynamic', 'override', 'abstract');

function CollapseSpace(const AText: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
  Space: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Space := False;
    for Index := 1 to Length(AText) do
      if CharInSet(AText[Index], [' ', #9, #10, #13]) then
        Space := True
      else
      begin
        if Space and (Builder.Length > 0) then
          Builder.Append(' ');
        Space := False;
        Builder.Append(AText[Index]);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function IsIdentifier(const AName: string): Boolean;
var
  Name: string;
  Index: Integer;
begin
  Name := AName;
  if Name.StartsWith('&') then
    Name := Name.Substring(1);
  Result := (Name <> '') and (CharInSet(Name[1], ['A'..'Z', 'a'..'z', '_']) or (Ord(Name[1]) > 127) and
    Name[1].IsLetter);
  if not Result then
    Exit;
  for Index := 2 to Length(Name) do
    if not (CharInSet(Name[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9']) or (Ord(Name[Index]) > 127) and
      Name[Index].IsLetterOrDigit) then
      Exit(False);
end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function TokenIndexAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Low_, High_, Middle: Integer;
begin
  Low_ := 0;
  High_ := Length(ATokens);
  while Low_ < High_ do
  begin
    Middle := (Low_ + High_) div 2;
    if ATokens[Middle].Offset < AOffset then
      Low_ := Middle + 1
    else
      High_ := Middle;
  end;
  Result := Low_;
end;

{ TClassMember }

function TClassMember.IsMethod: Boolean;
begin
  Result := Kind in [TClassMemberKind.Method, TClassMemberKind.Constructor_, TClassMemberKind.Destructor_];
end;

function TClassMember.IsFunction: Boolean;
begin
  Result := (Kind = TClassMemberKind.Method) and (TypeName <> '');
end;

function TClassMember.HasDirective(const AName: string): Boolean;
begin
  Result := IndexText(AName, Directives) >= 0;
end;

function TClassMember.IsVirtual: Boolean;
var
  Name: string;
begin
  for Name in VirtualDirectives do
    if HasDirective(Name) then
      Exit(True);
  Result := False;
end;

function TClassMember.IsAbstract: Boolean;
begin
  Result := HasDirective('abstract');
end;

function TClassMember.IsFieldGroup: Boolean;
begin
  Result := Length(GroupNames) > 1;
end;

{ TClassLayout }

class function TClassLayout.Read(ATree: TSyntaxTree; const AText: string; ADecl: TSyntaxNode): TClassLayout;
begin
  Result := TClassLayout.Create;
  try
    Result.FTree := ATree;
    Result.FText := AText;
    Result.FLines := TTextLines.SplitLines(AText, Result.LineBreak);
    Result.Decl := ADecl;
    Result.ClassNode := ADecl.FindChild(TSyntaxKind.ClassType);
    Result.Name := ADecl.Name;
    Result.ReadHeader;
    Result.ReadMembers;
    Result.FindBodies;
  except
    Result.Free;
    raise;
  end;
end;

function IsClassDecl(ANode: TSyntaxNode): Boolean;
var
  Body: TSyntaxNode;
begin
  Result := False;
  if ANode.Kind <> TSyntaxKind.TypeDecl then
    Exit;
  Body := ANode.FindChild(TSyntaxKind.ClassType);
  Result := Body <> nil;
end;

class function TClassLayout.AllDecls(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      // Rümpfe von Routinen enthalten keine Klassen, die ein Umbau anfasst.
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if Result and IsClassDecl(ANode) then
        Found := Found + [ANode];
    end);
  Result := Found;
end;

class function TClassLayout.DeclAt(ATree: TSyntaxTree; ALine: Integer; AInside: Boolean): TSyntaxNode;
var
  Decl: TSyntaxNode;
begin
  // Die innerste Klasse gewinnt (verschachtelte Typen stehen hinter ihrer äußeren in AllDecls).
  Result := nil;
  for Decl in AllDecls(ATree) do
    if (Decl.StartPos.Line = ALine) or AInside and (ALine >= Decl.StartPos.Line) and (ALine <= Decl.EndPos.Line) then
      Result := Decl;
end;

class function TClassLayout.DeclNamed(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  Decl: TSyntaxNode;
begin
  for Decl in AllDecls(ATree) do
    if SameText(Decl.Name, AName) then
      Exit(Decl);
  Result := nil;
end;

function TClassLayout.NodeText(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function TClassLayout.TextOf(ANode: TSyntaxNode): string;
begin
  Result := NodeText(ANode);
end;

function TClassLayout.TokenRange(AFirstOffset, ALastOffset: Integer; out AFirst, ALast: Integer): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Index: Integer;
begin
  Tokens := FTree.Tokens;
  AFirst := -1;
  ALast := -1;
  for Index := TokenIndexAt(Tokens, AFirstOffset) to High(Tokens) do
  begin
    if Tokens[Index].Offset >= ALastOffset then
      Break;
    if AFirst < 0 then
      AFirst := Index;
    ALast := Index;
  end;
  Result := AFirst >= 0;
end;

function TClassLayout.AfterClass(AOffset: Integer): Boolean;
var
  Index: Integer;
  Tokens: TArray<TPascalToken>;
begin
  Tokens := FTree.Tokens;
  Index := TokenIndexAt(Tokens, AOffset) - 1;
  while (Index >= 0) and IsTrivia(Tokens[Index]) do
    Dec(Index);
  Result := (Index >= 0) and Tokens[Index].IsKeyword('class');
end;

function TClassLayout.DocStart(ALine: Integer): Integer;
begin
  Result := -1;
  while (ALine > 0) and StartsText('///', Trim(FLines[ALine - 1])) do
  begin
    Dec(ALine);
    Result := ALine;
  end;
end;

procedure TClassLayout.ReadHeader;
var
  Tokens: TArray<TPascalToken>;
  First, Last, Index, Depth: Integer;
  Child, Params, Previous: TSyntaxNode;
  Doc: Integer;
begin
  HeaderLine := Decl.StartPos.Line;
  FirstLine := HeaderLine;
  // Attribute stehen als Geschwister vor der Deklaration.
  Previous := nil;
  if Decl.Parent <> nil then
    for Index := 0 to Decl.Parent.ChildCount - 1 do
      if Decl.Parent[Index] = Decl then
      begin
        Depth := Index - 1;
        while (Depth >= 0) and (Decl.Parent[Depth].Kind = TSyntaxKind.Attribute) do
        begin
          Previous := Decl.Parent[Depth];
          Dec(Depth);
        end;
        Break;
      end;
  if Previous <> nil then
    FirstLine := Previous.StartPos.Line;
  Doc := DocStart(FirstLine);
  if Doc >= 0 then
    FirstLine := Doc;
  Indent := TTextLines.IndentOf(FLines[HeaderLine]);
  EndLine := ClassNode.EndPos.Line;
  InInterface := False;
  Child := Decl.Parent;
  while Child <> nil do
  begin
    if Child.Kind = TSyntaxKind.InterfaceSection then
      InInterface := True;
    Child := Child.Parent;
  end;
  Params := Decl.FindChild(TSyntaxKind.GenericParams);
  if Params <> nil then
    GenericParams := CollapseSpace(NodeText(Params));
  Ancestors := nil;
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    if Child.Kind <> TSyntaxKind.TypeReference then
      Break;
    Ancestors := Ancestors + [CollapseSpace(NodeText(Child))];
  end;
  // Klammern der Vorfahrenliste und Stelle hinter class [abstract|sealed].
  HeritageOpen := -1;
  HeritageClose := -1;
  HeritageInsert := ClassNode.StartOffset + Length('class');
  Tokens := FTree.Tokens;
  if TokenRange(ClassNode.StartOffset, ClassNode.EndOffset, First, Last) then
  begin
    Index := First + 1;
    while (Index <= Last) and IsTrivia(Tokens[Index]) do
      Inc(Index);
    if (Index <= Last) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      MatchText(Tokens[Index].Text, ['abstract', 'sealed']) then
    begin
      HeritageInsert := Tokens[Index].Offset + Length(Tokens[Index].Text);
      Inc(Index);
      while (Index <= Last) and IsTrivia(Tokens[Index]) do
        Inc(Index);
    end;
    if (Index <= Last) and Tokens[Index].IsSymbol('(') then
    begin
      HeritageOpen := Tokens[Index].Offset;
      Depth := 0;
      while Index <= Last do
      begin
        if Tokens[Index].IsSymbol('(') then
          Inc(Depth)
        else if Tokens[Index].IsSymbol(')') then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            HeritageClose := Tokens[Index].Offset;
            Break;
          end;
        end;
        Inc(Index);
      end;
    end;
  end;
  MemberIndent := Indent + '  ';
end;

const
  PropertySpecifiers: array[0..7] of string = ('read', 'write', 'index', 'stored', 'default', 'nodefault',
    'implements', 'dispid');

/// <summary>Wert hinter dem Spezifizierer AKeyword einer Property zwischen den Token AFirst und ALast (bis zum
/// nächsten Spezifizierer bzw. Semikolon); '' ohne.</summary>
function SpecifierAfter(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; const AKeyword: string): string;
var
  Index: Integer;
begin
  Result := '';
  Index := AFirst;
  while Index <= ALast do
  begin
    if not IsTrivia(ATokens[Index]) and (ATokens[Index].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword]) and SameText(ATokens[Index].Text, AKeyword) then
    begin
      Inc(Index);
      while (Index <= ALast) and not ATokens[Index].IsSymbol(';') and
        not ((ATokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
        MatchText(ATokens[Index].Text, PropertySpecifiers)) do
      begin
        if not IsTrivia(ATokens[Index]) then
          Result := Result + ATokens[Index].Text;
        Inc(Index);
      end;
      Exit;
    end;
    if ATokens[Index].IsSymbol(';') then
      Exit;
    Inc(Index);
  end;
end;

procedure TClassLayout.ReadMembers;
var
  Index, Part, Pending, First, Last, Next: Integer;
  Child, Inner, TypeRef, Parameters, Parameter: TSyntaxNode;
  Visibility: TClassVisibility;
  Section: TClassSection;
  Member: TClassMember;
  Head, Text, Names, TypeText: string;
  GroupNames: TArray<string>;
  IsClassPrefix: Boolean;

  procedure Add(const AMember: TClassMember);
  begin
    Members := Members + [AMember];
    Section.Members := Section.Members + [High(Members)];
  end;

  function NewMember(AKind: TClassMemberKind; ANode: TSyntaxNode; const AName: string): TClassMember;
  begin
    Result := Default(TClassMember);
    Result.Kind := AKind;
    Result.Node := ANode;
    Result.Name := AName;
    Result.GroupNames := [AName];
    Result.Visibility := Visibility;
    Result.FirstLine := ANode.StartPos.Line;
    if Pending >= 0 then
      Result.FirstLine := Pending;
    Result.DocLine := DocStart(Result.FirstLine);
    if Result.DocLine >= 0 then
      Result.FirstLine := Result.DocLine;
    Result.LastLine := ANode.EndPos.Line;
    Result.BodyFirstLine := -1;
    Result.BodyLastLine := -1;
  end;

begin
  Members := nil;
  Sections := nil;
  Visibility := TClassVisibility.Public_;
  Section := Default(TClassSection);
  Section.Visibility := Visibility;
  Section.HeadLine := -1;
  Pending := -1;
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    case Child.Kind of
      TSyntaxKind.TypeReference:
        Continue;
      TSyntaxKind.Visibility:
        begin
          if (Section.HeadLine >= 0) or (Section.Members <> nil) then
            Sections := Sections + [Section];
          Visibility := TClassEdits.VisibilityOf(Child.Name);
          Section := Default(TClassSection);
          Section.Visibility := Visibility;
          Section.HeadLine := Child.StartPos.Line;
          Pending := -1;
        end;
      TSyntaxKind.Attribute:
        if Pending < 0 then
          Pending := Child.StartPos.Line;
      TSyntaxKind.Field:
        begin
          GroupNames := nil;
          for Names in Child.Name.Split([',']) do
            GroupNames := GroupNames + [Trim(Names)];
          TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
          TypeText := '';
          if Child.ChildCount > 0 then
            TypeText := CollapseSpace(NodeText(Child[0]));
          if TypeRef <> nil then
            TypeText := CollapseSpace(NodeText(TypeRef));
          for Part := 0 to High(GroupNames) do
          begin
            Member := NewMember(TClassMemberKind.Field, Child, GroupNames[Part]);
            Member.GroupNames := GroupNames;
            Member.TypeName := TypeText;
            Add(Member);
          end;
          Pending := -1;
        end;
      TSyntaxKind.VarSection:
        begin
          // class var bzw. var-Abschnitt in der Klasse: je Name ein Mitglied.
          IsClassPrefix := AfterClass(Child.StartOffset);
          for Part := 0 to Child.ChildCount - 1 do
          begin
            Inner := Child[Part];
            if Inner.Kind <> TSyntaxKind.VarDecl then
              Continue;
            GroupNames := nil;
            for Names in Inner.Name.Split([',']) do
              GroupNames := GroupNames + [Trim(Names)];
            TypeRef := Inner.FindChild(TSyntaxKind.TypeReference);
            for Names in GroupNames do
            begin
              if IsClassPrefix then
                Member := NewMember(TClassMemberKind.ClassVar, Inner, Names)
              else
                Member := NewMember(TClassMemberKind.Field, Inner, Names);
              Member.GroupNames := GroupNames;
              Member.IsClassMember := IsClassPrefix;
              if TypeRef <> nil then
                Member.TypeName := CollapseSpace(NodeText(TypeRef));
              Add(Member);
            end;
          end;
          Pending := -1;
        end;
      TSyntaxKind.RoutineHeader:
        begin
          if Child.IsMethodResolution then
          begin
            Pending := -1;
            Continue;
          end;
          Head := TrimLeft(Copy(FText, Child.StartOffset + 1, 40));
          Member := NewMember(TClassMemberKind.Method, Child, Child.Name);
          Member.IsClassMember := StartsText('class', Head) and (Length(Head) > 5) and not Head[6].IsLetterOrDigit;
          if Member.IsClassMember then
            Head := TrimLeft(Copy(Head, 6, MaxInt));
          if StartsText('constructor', Head) then
            Member.Kind := TClassMemberKind.Constructor_
          else if StartsText('destructor', Head) then
            Member.Kind := TClassMemberKind.Destructor_
          else if StartsText('operator', Head) then
            Member.Kind := TClassMemberKind.Other;
          Member.IsGeneric := Child.FindChild(TSyntaxKind.GenericParams) <> nil;
          for Part := 0 to Child.ChildCount - 1 do
          begin
            Inner := Child[Part];
            if Inner.Kind = TSyntaxKind.TypeReference then
              Member.TypeName := CollapseSpace(NodeText(Inner))
            else if Inner.Kind = TSyntaxKind.Directive then
              Member.Directives := Member.Directives + [Inner.Name];
          end;
          Parameters := Child.FindChild(TSyntaxKind.Parameters);
          if Parameters <> nil then
          begin
            Text := NodeText(Parameters);
            Member.Parameters := CollapseSpace(Copy(Text, 2, Length(Text) - 2));
            for Part := 0 to Parameters.ChildCount - 1 do
            begin
              Parameter := Parameters[Part];
              TypeRef := Parameter.FindChild(TSyntaxKind.TypeReference);
              if TypeRef = nil then
                TypeRef := Parameter.FindChild(TSyntaxKind.ArrayType);
              TypeText := '';
              if TypeRef <> nil then
                TypeText := CollapseSpace(NodeText(TypeRef));
              for Names in Parameter.Name.Split([',']) do
                Member.ParameterTypes := Member.ParameterTypes + [UpperCase(TypeText)];
            end;
          end;
          Add(Member);
          Pending := -1;
        end;
      TSyntaxKind.PropertyDecl:
        begin
          Member := NewMember(TClassMemberKind.Property_, Child, Child.Name);
          Member.IsClassMember := AfterClass(Child.StartOffset);
          TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
          Member.IsRedeclaration := TypeRef = nil;
          if TypeRef <> nil then
            Member.TypeName := CollapseSpace(NodeText(TypeRef));
          Parameters := Child.FindChild(TSyntaxKind.Parameters);
          if Parameters <> nil then
          begin
            Head := NodeText(Parameters);
            Member.Parameters := CollapseSpace(Copy(Head, 2, Length(Head) - 2));
          end;
          // Spezifizierer erst hinter dem Typ suchen, damit Parameternamen wie "Index" nicht stören.
          TokenRange(Child.StartOffset, Child.EndOffset, First, Last);
          if TypeRef <> nil then
            TokenRange(TypeRef.EndOffset, Child.EndOffset, First, Last);
          if First >= 0 then
          begin
            Member.ReadAccessor := SpecifierAfter(FTree.Tokens, First, Last, 'read');
            Member.WriteAccessor := SpecifierAfter(FTree.Tokens, First, Last, 'write');
            Member.IndexSpecifier := SpecifierAfter(FTree.Tokens, First, Last, 'index');
            Member.StoredSpecifier := SpecifierAfter(FTree.Tokens, First, Last, 'stored');
            // "; default;" hinter dem Semikolon der Deklaration.
            for Part := First to Last - 1 do
              if FTree.Tokens[Part].IsSymbol(';') then
              begin
                Next := Part + 1;
                while (Next <= Last) and IsTrivia(FTree.Tokens[Next]) do
                  Inc(Next);
                Member.IsDefaultArray := (Next <= Last) and SameText(FTree.Tokens[Next].Text, 'default');
                Break;
              end;
          end;
          Add(Member);
          Pending := -1;
        end;
    else
      begin
        // Konstanten, verschachtelte Typen, variante Teile: zählen als Zeilen, sind aber keine Umbauziele.
        Member := NewMember(TClassMemberKind.Other, Child, Child.Name);
        Add(Member);
        Pending := -1;
      end;
    end;
  end;
  Sections := Sections + [Section];
end;

procedure TClassLayout.FindBodies;
var
  Index, Other, Doc: Integer;
  Prefix: string;
  Routines: TArray<TSyntaxNode>;
  Routine, Header, Parameters, Parameter, TypeRef: TSyntaxNode;
  Types: TArray<string>;
  Names: string;
  Overloaded: Boolean;

  function SameTypes(const A, B: TArray<string>): Boolean;
  var
    Position: Integer;
  begin
    Result := Length(A) = Length(B);
    if Result then
      for Position := 0 to High(A) do
        if not SameText(A[Position], B[Position]) then
          Exit(False);
  end;

begin
  Prefix := Decl.EnclosingTypeName;
  if Prefix = '' then
    Prefix := Name;
  Routines := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(Prefix + '.', ANode.Name) and
        (Pos('.', Copy(ANode.Name, Length(Prefix) + 2, MaxInt)) = 0) then
        Routines := Routines + [ANode];
    end);
  for Index := 0 to High(Members) do
  begin
    if not Members[Index].IsMethod and (Members[Index].Kind <> TClassMemberKind.Other) then
      Continue;
    if (Members[Index].Kind = TClassMemberKind.Other) and (Members[Index].Node.Kind <> TSyntaxKind.RoutineHeader) then
      Continue;
    Overloaded := False;
    for Other := 0 to High(Members) do
      if (Other <> Index) and Members[Other].IsMethod and SameText(Members[Other].Name, Members[Index].Name) then
        Overloaded := True;
    for Routine in Routines do
    begin
      if not SameText(Routine.Name, Prefix + '.' + Members[Index].Name) then
        Continue;
      if Overloaded then
      begin
        Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
        Types := nil;
        Parameters := nil;
        if Header <> nil then
          Parameters := Header.FindChild(TSyntaxKind.Parameters);
        if Parameters <> nil then
          for Other := 0 to Parameters.ChildCount - 1 do
          begin
            Parameter := Parameters[Other];
            TypeRef := Parameter.FindChild(TSyntaxKind.TypeReference);
            if TypeRef = nil then
              TypeRef := Parameter.FindChild(TSyntaxKind.ArrayType);
            for Names in Parameter.Name.Split([',']) do
              if TypeRef <> nil then
                Types := Types + [UpperCase(CollapseSpace(NodeText(TypeRef)))]
              else
                Types := Types + [''];
          end;
        if not SameTypes(Types, Members[Index].ParameterTypes) then
          Continue;
      end;
      Members[Index].Body := Routine;
      Members[Index].BodyFirstLine := Routine.StartPos.Line;
      Doc := DocStart(Routine.StartPos.Line);
      if Doc >= 0 then
        Members[Index].BodyFirstLine := Doc;
      Members[Index].BodyLastLine := Routine.EndPos.Line;
      Break;
    end;
  end;
end;

function TClassLayout.Find(const AName: string): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(Members) do
    if SameText(Members[Index].Name, AName) then
      Result := Result + [Index];
end;

function TClassLayout.MemberAtLine(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Members) do
    if (ALine >= Members[Index].FirstLine) and (ALine <= Members[Index].LastLine) and
      (Members[Index].Kind <> TClassMemberKind.Other) then
      Exit(Index);
  Result := -1;
end;

/// <summary>Bezeichner im Offsetbereich, die als Mitglied der eigenen Klasse gemeint sein können: ohne Punkt
/// davor oder hinter Self.</summary>
function MemberNames(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<string>;
var
  Index, Previous, Before: Integer;
begin
  Result := nil;
  for Index := 0 to High(ATokens) do
  begin
    if ATokens[Index].Offset < AFirst then
      Continue;
    if ATokens[Index].Offset >= ALast then
      Break;
    if ATokens[Index].Kind <> TPascalTokenKind.Identifier then
      Continue;
    Previous := Index - 1;
    while (Previous >= 0) and IsTrivia(ATokens[Previous]) do
      Dec(Previous);
    if (Previous >= 0) and ATokens[Previous].IsSymbol('.') then
    begin
      Before := Previous - 1;
      while (Before >= 0) and IsTrivia(ATokens[Before]) do
        Dec(Before);
      if (Before < 0) or not SameText(ATokens[Before].Text, 'Self') then
        Continue;
    end;
    Result := Result + [ATokens[Index].Text];
  end;
end;

function TClassLayout.UsedBy(AIndex: Integer): TArray<Integer>;
var
  Names: TArray<string>;
  Member: TClassMember;
  Index, Other: Integer;
  Body: TSyntaxNode;
  Start: Integer;
begin
  Member := Members[AIndex];
  Names := nil;
  if Member.Kind = TClassMemberKind.Property_ then
    Names := MemberNames(FTree.Tokens, Member.Node.StartOffset, Member.Node.EndOffset);
  Body := Member.Body;
  if Body <> nil then
  begin
    // Ohne den Kopf: dessen Name ist kein Aufruf.
    Start := Body.StartOffset;
    if Body.FindChild(TSyntaxKind.RoutineHeader) <> nil then
      Start := Body.FindChild(TSyntaxKind.RoutineHeader).EndOffset;
    Names := Names + MemberNames(FTree.Tokens, Start, Body.EndOffset);
  end;
  Result := nil;
  for Index := 0 to High(Members) do
  begin
    if (Index = AIndex) or (Members[Index].Kind = TClassMemberKind.Other) then
      Continue;
    for Other := 0 to High(Names) do
      if SameText(Names[Other], Members[Index].Name) then
      begin
        Result := Result + [Index];
        Break;
      end;
  end;
  // Der Name der Property selbst ist keine Verwendung.
  if Member.Kind = TClassMemberKind.Property_ then
    for Index := High(Result) downto 0 do
      if SameText(Members[Result[Index]].Name, Member.Name) then
        Delete(Result, Index, 1);
end;

function TClassLayout.UsersOf(AIndex: Integer): TArray<Integer>;
var
  Index, Used: Integer;
begin
  Result := nil;
  for Index := 0 to High(Members) do
  begin
    if (Index = AIndex) or (Members[Index].Kind = TClassMemberKind.Other) then
      Continue;
    for Used in UsedBy(Index) do
      if SameText(Members[Used].Name, Members[AIndex].Name) then
      begin
        Result := Result + [Index];
        Break;
      end;
  end;
end;

function TClassLayout.Declaration(AIndex: Integer): string;
var
  Member: TClassMember;
begin
  Member := Members[AIndex];
  if Member.IsFieldGroup or (Member.Kind = TClassMemberKind.ClassVar) or (Member.Node.Kind = TSyntaxKind.VarDecl)
  then
  begin
    Result := Member.Name + ': ' + Member.TypeName + ';';
    if Member.Kind = TClassMemberKind.ClassVar then
      Result := 'class var ' + Result;
    Exit;
  end;
  Result := CollapseSpace(NodeText(Member.Node));
  if Member.IsClassMember and (Member.Kind = TClassMemberKind.Property_) then
    Result := 'class ' + Result;
  if not Result.EndsWith(';') then
    Result := Result + ';';
end;

function TClassLayout.DocLines(AIndex: Integer): TArray<string>;
var
  Line, Stop: Integer;
begin
  Result := nil;
  if Members[AIndex].DocLine < 0 then
    Exit;
  Stop := Members[AIndex].Node.StartPos.Line - 1;
  for Line := Members[AIndex].DocLine to Stop do
    if StartsText('///', Trim(FLines[Line])) then
      Result := Result + [Trim(FLines[Line])];
end;

function TClassLayout.Head(AIndex: Integer): string;
var
  Member: TClassMember;
  Node, Child: TSyntaxNode;
  Stop, Index: Integer;
begin
  Member := Members[AIndex];
  Node := Member.Node;
  if Node.Kind <> TSyntaxKind.RoutineHeader then
    Exit(Declaration(AIndex));
  Stop := Node.EndOffset;
  for Index := 0 to Node.ChildCount - 1 do
  begin
    Child := Node[Index];
    if Child.Kind = TSyntaxKind.Directive then
    begin
      Stop := Child.StartOffset;
      Break;
    end;
  end;
  Result := CollapseSpace(Copy(FText, Node.StartOffset + 1, Stop - Node.StartOffset));
  if not Result.EndsWith(';') then
    Result := Result + ';';
end;

function TClassLayout.LinesText(AFirst, ALast: Integer): string;
var
  Line: Integer;
begin
  Result := '';
  for Line := AFirst to ALast do
    Result := Result + FLines[Line] + LineBreak;
end;

{ TClassEdits }

class function TClassEdits.VisibilityName(AVisibility: TClassVisibility): string;
begin
  case AVisibility of
    TClassVisibility.StrictPrivate:
      Result := 'strict private';
    TClassVisibility.Private_:
      Result := 'private';
    TClassVisibility.StrictProtected:
      Result := 'strict protected';
    TClassVisibility.Protected_:
      Result := 'protected';
    TClassVisibility.Published_:
      Result := 'published';
  else
    Result := 'public';
  end;
end;

class function TClassEdits.VisibilityOf(const AName: string): TClassVisibility;
var
  Name: string;
begin
  Name := LowerCase(CollapseSpace(AName));
  if Name = 'strict private' then
    Result := TClassVisibility.StrictPrivate
  else if Name = 'private' then
    Result := TClassVisibility.Private_
  else if Name = 'strict protected' then
    Result := TClassVisibility.StrictProtected
  else if Name = 'protected' then
    Result := TClassVisibility.Protected_
  else if Name = 'published' then
    Result := TClassVisibility.Published_
  else
    Result := TClassVisibility.Public_;
end;

class function TClassEdits.DeleteLines(ALayout: TClassLayout; AFirst, ALast: Integer): TTextEdit;
var
  Lines: TArray<string>;
begin
  Lines := ALayout.Lines;
  // Eine Leerzeile dahinter mitnehmen, wenn davor auch eine steht (Rümpfe sind durch Leerzeilen getrennt).
  if (ALast + 1 <= High(Lines)) and (Trim(Lines[ALast + 1]) = '') and (AFirst > 0) and
    (Trim(Lines[AFirst - 1]) = '') then
    Inc(ALast);
  Result := TTextEdit.Create(TTextRange.Create(AFirst, 0, ALast + 1, 0), '');
end;

class function TClassEdits.DeleteMember(ALayout: TClassLayout; AIndex: Integer;
  ABody: Boolean): TArray<TTextEdit>;
begin
  Result := DeleteMembers(ALayout, [AIndex], ABody);
end;

class function TClassEdits.DeleteMembers(ALayout: TClassLayout; const AIndexes: TArray<Integer>;
  ABodies: Boolean): TArray<TTextEdit>;
var
  Index, Other: Integer;
  Member: TClassMember;
  Remaining: TArray<string>;
  Done: TArray<TSyntaxNode>;
  Name, Declaration: string;
  Dropped: Boolean;
  Node: TSyntaxNode;
  Range: TTextRange;
  Table: TLineTable;
begin
  Result := nil;
  Done := nil;
  Table := TLineTable.Build(ALayout.Text);
  for Index in AIndexes do
  begin
    Member := ALayout.Members[Index];
    Node := Member.Node;
    Dropped := False;
    for Other := 0 to High(Done) do
      if Done[Other] = Node then
        Dropped := True;
    if Dropped then
      Continue;
    Done := Done + [Node];
    if Member.IsFieldGroup then
    begin
      // Übrige Namen der Gruppe behalten.
      Remaining := nil;
      for Name in Member.GroupNames do
      begin
        Dropped := False;
        for Other in AIndexes do
          if (ALayout.Members[Other].Node = Node) and SameText(ALayout.Members[Other].Name, Name) then
            Dropped := True;
        if not Dropped then
          Remaining := Remaining + [Name];
      end;
      if Remaining <> nil then
      begin
        Declaration := string.Join(', ', Remaining) + ': ' + Member.TypeName + ';';
        Range := TTextRange.Create(Table.PositionAt(Node.StartOffset), Table.PositionAt(Node.EndOffset));
        Result := Result + [TTextEdit.Create(Range, Declaration)];
        Continue;
      end;
    end;
    if (Node.Kind = TSyntaxKind.VarDecl) and (Node.Parent <> nil) and (Node.Parent.ChildCount = 1) then
      // Einziger Eintrag eines var-Abschnitts: der ganze Abschnitt samt "class var".
      Result := Result + [TTextEdit.Create(TTextRange.Create(Node.Parent.StartPos.Line, 0, Member.LastLine + 1, 0),
        '')]
    else
      Result := Result + [TTextEdit.Create(TTextRange.Create(Member.FirstLine, 0, Member.LastLine + 1, 0), '')];
    if ABodies and (Member.Body <> nil) then
      Result := Result + [DeleteLines(ALayout, Member.BodyFirstLine, Member.BodyLastLine)];
  end;
end;

class function TClassEdits.InsertMembers(ALayout: TClassLayout; AVisibility: TClassVisibility; AFields: Boolean;
  const ADeclarations: TArray<string>): TTextEdit;
var
  Section: TClassSection;
  Found, Index, Line: Integer;
  Body, Item, Part: string;
  Member: TClassMember;
begin
  Body := '';
  for Item in ADeclarations do
    for Part in Item.Split([#10]) do
      Body := Body + ALayout.MemberIndent + TrimRight(Part) + ALayout.LineBreak;
  Found := -1;
  for Index := 0 to High(ALayout.Sections) do
    if (ALayout.Sections[Index].Visibility = AVisibility) and
      ((ALayout.Sections[Index].HeadLine >= 0) or (AVisibility = TClassVisibility.Public_)) then
      Found := Index;
  if Found < 0 then
  begin
    // Neuer Abschnitt in der Reihenfolge der Sichtbarkeit: vor den ersten mit höherer, sonst vor end.
    Line := ALayout.EndLine;
    for Index := High(ALayout.Sections) downto 0 do
      if (ALayout.Sections[Index].HeadLine >= 0) and (ALayout.Sections[Index].Visibility > AVisibility) then
        Line := ALayout.Sections[Index].HeadLine;
    Result := InsertBeforeLine(ALayout.Text, Line, ALayout.Indent + VisibilityName(AVisibility) +
      ALayout.LineBreak + Body);
    Exit;
  end;
  Section := ALayout.Sections[Found];
  if AFields then
    for Index in Section.Members do
    begin
      Member := ALayout.Members[Index];
      if Member.IsMethod or (Member.Kind = TClassMemberKind.Property_) then
        Exit(InsertBeforeLine(ALayout.Text, Member.FirstLine, Body));
    end;
  // Hinter das letzte Mitglied bzw. die Kopfzeile des Abschnitts.
  Line := Section.HeadLine;
  if Line < 0 then
    Line := ALayout.HeaderLine;
  for Index in Section.Members do
    if ALayout.Members[Index].LastLine > Line then
      Line := ALayout.Members[Index].LastLine;
  Result := InsertBeforeLine(ALayout.Text, Line + 1, Body);
end;

class function TClassEdits.SetAncestors(ALayout: TClassLayout; const AAncestors: TArray<string>): TTextEdit;
var
  Table: TLineTable;
  List: string;
begin
  Table := TLineTable.Build(ALayout.Text);
  List := '';
  if AAncestors <> nil then
    List := '(' + string.Join(', ', AAncestors) + ')';
  if ALayout.HeritageOpen >= 0 then
    Result := TTextEdit.Create(TTextRange.Create(Table.PositionAt(ALayout.HeritageOpen),
      Table.PositionAt(ALayout.HeritageClose + 1)), List)
  else
    Result := TTextEdit.Create(TTextRange.Create(Table.PositionAt(ALayout.HeritageInsert),
      Table.PositionAt(ALayout.HeritageInsert)), List);
end;

class function TClassEdits.BodyText(ALayout: TClassLayout; AIndex: Integer; const AClassName: string): string;
var
  Member: TClassMember;
  Text: string;
  Offset, Start, Index: Integer;
  Table: TLineTable;
  Tokens: TArray<TPascalToken>;
begin
  Member := ALayout.Members[AIndex];
  if Member.Body = nil then
    Exit('');
  Table := TLineTable.Build(ALayout.Text);
  Start := Table.LineStart(Member.BodyFirstLine);
  Text := Copy(ALayout.Text, Start + 1, Member.Body.EndOffset - Start);
  // Klassenname im Kopf ersetzen: erster Bezeichner mit dem Namen der Klasse (Typparameter bleiben).
  Tokens := ALayout.Tree.Tokens;
  for Index := TokenIndexAt(Tokens, Member.Body.StartOffset) to High(Tokens) do
  begin
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol(';') then
      Break;
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, ALayout.Name) then
    begin
      Offset := Tokens[Index].Offset - Start;
      Text := Copy(Text, 1, Offset) + AClassName + Copy(Text, Offset + Length(Tokens[Index].Text) + 1, MaxInt);
      Break;
    end;
  end;
  Result := Text;
end;

class function TClassEdits.BodiesEnd(ATree: TSyntaxTree; const AText, AClassName: string): Integer;
var
  Last: Integer;
  Implementation_: TSyntaxNode;
  Index: Integer;
begin
  Last := -1;
  Implementation_ := nil;
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.ImplementationSection then
        Implementation_ := ANode;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(AClassName + '.', ANode.Name) and (ANode.EndPos.Line > Last) then
        Last := ANode.EndPos.Line;
    end);
  if Last >= 0 then
    Exit(Last);
  if Implementation_ = nil then
    Exit(-1);
  // Hinter die letzte Deklaration der implementation, sonst hinter "implementation" bzw. dessen uses.
  Result := Implementation_.StartPos.Line;
  for Index := 0 to Implementation_.ChildCount - 1 do
    if Implementation_[Index].EndPos.Line > Result then
      Result := Implementation_[Index].EndPos.Line;
end;

class function TClassEdits.InsertBodies(const AText: string; ALine: Integer;
  const ABodies: TArray<string>): TTextEdit;
var
  LineBreak, Body, NewText: string;
begin
  LineBreak := TTextLines.LineBreakOf(AText);
  NewText := '';
  for Body in ABodies do
    NewText := NewText + LineBreak + Body + LineBreak;
  Result := InsertBeforeLine(AText, ALine + 1, NewText);
end;

class function TClassEdits.ReplaceAccessor(ALayout: TClassLayout; AIndex: Integer; const AKeyword,
  ANewName: string; out AEdit: TTextEdit): Boolean;
var
  Node, TypeRef: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Index, Start, Next: Integer;
begin
  Node := ALayout.Members[AIndex].Node;
  Start := Node.StartOffset;
  TypeRef := Node.FindChild(TSyntaxKind.TypeReference);
  if TypeRef <> nil then
    Start := TypeRef.EndOffset;
  Tokens := ALayout.Tree.Tokens;
  Index := TokenIndexAt(Tokens, Start);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) and not Tokens[Index].IsSymbol(';') do
  begin
    if (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(Tokens[Index].Text, AKeyword) then
    begin
      Next := Index + 1;
      while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
        Inc(Next);
      if (Next > High(Tokens)) or (Tokens[Next].Kind <> TPascalTokenKind.Identifier) then
        Exit(False);
      AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Next].StartPos, Tokens[Next].EndPos), ANewName);
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

class function TClassEdits.InsertBeforeLine(const AText: string; ALine: Integer;
  const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), ANewText);
end;

end.
