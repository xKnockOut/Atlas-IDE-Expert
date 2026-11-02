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
    class function BodiesEnd(ATree: TSyntaxTree; const AClassName: string): Integer; static;
    /// <summary>Rümpfe ABodies (je ein Text, ohne Umbruch am Ende) hinter Zeile ALine einfügen, je durch eine
    /// Leerzeile getrennt.</summary>
    class function InsertBodies(const AText: string; ALine: Integer; const ABodies: TArray<string>): TTextEdit;
      static;
    /// <summary>Den Namen hinter AKeyword (read, write) der Property AIndex durch ANewName ersetzen; False ohne
    /// diesen Spezifizierer.</summary>
    class function ReplaceAccessor(ALayout: TClassLayout; AIndex: Integer; const AKeyword, ANewName: string;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Text am Anfang der Zeile ALine einfügen.</summary>
    class function InsertBeforeLine(ALine: Integer; const ANewText: string): TTextEdit; static;
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
    begin
      if CharInSet(AText[Index], [' ', #9, #10, #13]) then
      begin
        Space := True;
      end
      else
      begin
        if Space and (Builder.Length > 0) then
        begin
          Builder.Append(' ');
        end;
        Space := False;
        Builder.Append(AText[Index]);
      end;
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
  begin
    Name := Name.Substring(1);
  end;
  Result := (Name <> '') and (CharInSet(Name[1], ['A'..'Z', 'a'..'z', '_']) or (Ord(Name[1]) > 127) and
    Name[1].IsLetter);
  if not Result then
  begin
    Exit;
  end;
  for Index := 2 to Length(Name) do
  begin
    if not (CharInSet(Name[Index], ['A'..'Z', 'a'..'z', '_', '0'..'9']) or (Ord(Name[Index]) > 127) and
      Name[Index].IsLetterOrDigit) then
    begin
      Exit(False);
    end;
  end;
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
    begin
      Low_ := Middle + 1;
    end
    else
    begin
      High_ := Middle;
    end;
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
  begin
    if HasDirective(Name) then
    begin
      Exit(True);
    end;
  end;
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
  begin
    Exit;
  end;
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
      begin
        Found := Found + [ANode];
      end;
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
  begin
    if (Decl.StartPos.Line = ALine) or AInside and (ALine >= Decl.StartPos.Line) and (ALine <= Decl.EndPos.Line) then
    begin
      Result := Decl;
    end;
  end;
end;

class function TClassLayout.DeclNamed(ATree: TSyntaxTree; const AName: string): TSyntaxNode;
var
  Decl: TSyntaxNode;
begin
  for Decl in AllDecls(ATree) do
  begin
    if SameText(Decl.Name, AName) then
    begin
      Exit(Decl);
    end;
  end;
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
    begin
      Break;
    end;
    if AFirst < 0 then
    begin
      AFirst := Index;
    end;
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
  begin
    Dec(Index);
  end;
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
  begin
    for Index := 0 to Decl.Parent.ChildCount - 1 do
    begin
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
    end;
  end;
  if Previous <> nil then
  begin
    FirstLine := Previous.StartPos.Line;
  end;
  Doc := DocStart(FirstLine);
  if Doc >= 0 then
  begin
    FirstLine := Doc;
  end;
  Indent := TTextLines.IndentOf(FLines[HeaderLine]);
  EndLine := ClassNode.EndPos.Line;
  InInterface := False;
  Child := Decl.Parent;
  while Child <> nil do
  begin
    if Child.Kind = TSyntaxKind.InterfaceSection then
    begin
      InInterface := True;
    end;
    Child := Child.Parent;
  end;
  Params := Decl.FindChild(TSyntaxKind.GenericParams);
  if Params <> nil then
  begin
    GenericParams := CollapseSpace(NodeText(Params));
  end;
  Ancestors := nil;
  for Index := 0 to ClassNode.ChildCount - 1 do
  begin
    Child := ClassNode[Index];
    if Child.Kind <> TSyntaxKind.TypeReference then
    begin
      Break;
    end;
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
    begin
      Inc(Index);
    end;
    if (Index <= Last) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
      MatchText(Tokens[Index].Text, ['abstract', 'sealed']) then
    begin
      HeritageInsert := Tokens[Index].Offset + Length(Tokens[Index].Text);
      Inc(Index);
      while (Index <= Last) and IsTrivia(Tokens[Index]) do
      begin
        Inc(Index);
      end;
    end;
    if (Index <= Last) and Tokens[Index].IsSymbol('(') then
    begin
      HeritageOpen := Tokens[Index].Offset;
      Depth := 0;
      while Index <= Last do
      begin
        if Tokens[Index].IsSymbol('(') then
        begin
          Inc(Depth);
        end
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
        begin
          Result := Result + ATokens[Index].Text;
        end;
        Inc(Index);
      end;
      Exit;
    end;
    if ATokens[Index].IsSymbol(';') then
    begin
      Exit;
    end;
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
  Head, mText, Names, TypeText: string;
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
    begin
      Result.FirstLine := Pending;
    end;
    Result.DocLine := DocStart(Result.FirstLine);
    if Result.DocLine >= 0 then
    begin
      Result.FirstLine := Result.DocLine;
    end;
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
          begin
            Sections := Sections + [Section];
          end;
          Visibility := TClassEdits.VisibilityOf(Child.Name);
          Section := Default(TClassSection);
          Section.Visibility := Visibility;
          Section.HeadLine := Child.StartPos.Line;
          Pending := -1;
        end;
      TSyntaxKind.Attribute:
        if Pending < 0 then
        begin
          Pending := Child.StartPos.Line;
        end;
      TSyntaxKind.Field:
        begin
          GroupNames := nil;
          for Names in Child.Name.Split([',']) do
          begin
            GroupNames := GroupNames + [Trim(Names)];
          end;
          TypeRef := Child.FindChild(TSyntaxKind.TypeReference);
          TypeText := '';
          if Child.ChildCount > 0 then
          begin
            TypeText := CollapseSpace(NodeText(Child[0]));
          end;
          if TypeRef <> nil then
          begin
            TypeText := CollapseSpace(NodeText(TypeRef));
          end;
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
            begin
              Continue;
            end;
            GroupNames := nil;
            for Names in Inner.Name.Split([',']) do
            begin
              GroupNames := GroupNames + [Trim(Names)];
            end;
            TypeRef := Inner.FindChild(TSyntaxKind.TypeReference);
            for Names in GroupNames do
            begin
              if IsClassPrefix then
              begin
                Member := NewMember(TClassMemberKind.ClassVar, Inner, Names);
              end
              else
              begin
                Member := NewMember(TClassMemberKind.Field, Inner, Names);
              end;
              Member.GroupNames := GroupNames;
              Member.IsClassMember := IsClassPrefix;
              if TypeRef <> nil then
              begin
                Member.TypeName := CollapseSpace(NodeText(TypeRef));
              end;
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
          begin
            Head := TrimLeft(Copy(Head, 6, MaxInt));
          end;
          if StartsText('constructor', Head) then
          begin
            Member.Kind := TClassMemberKind.Constructor_;
          end
          else if StartsText('destructor', Head) then
          begin
            Member.Kind := TClassMemberKind.Destructor_;
          end
          else if StartsText('operator', Head) then
          begin
            Member.Kind := TClassMemberKind.Other;
          end;
          Member.IsGeneric := Child.FindChild(TSyntaxKind.GenericParams) <> nil;
          for Part := 0 to Child.ChildCount - 1 do
          begin
            Inner := Child[Part];
            if Inner.Kind = TSyntaxKind.TypeReference then
            begin
              Member.TypeName := CollapseSpace(NodeText(Inner));
            end
            else if Inner.Kind = TSyntaxKind.Directive then
            begin
              Member.Directives := Member.Directives + [Inner.Name];
            end;
          end;
          Parameters := Child.FindChild(TSyntaxKind.Parameters);
          if Parameters <> nil then
          begin
            mText := NodeText(Parameters);
            Member.Parameters := CollapseSpace(Copy(mText, 2, Length(mText) - 2));
            for Part := 0 to Parameters.ChildCount - 1 do
            begin
              Parameter := Parameters[Part];
              TypeRef := Parameter.FindChild(TSyntaxKind.TypeReference);
              if TypeRef = nil then
              begin
                TypeRef := Parameter.FindChild(TSyntaxKind.ArrayType);
              end;
              TypeText := '';
              if TypeRef <> nil then
              begin
                TypeText := CollapseSpace(NodeText(TypeRef));
              end;
              for Names in Parameter.Name.Split([',']) do
              begin
                Member.ParameterTypes := Member.ParameterTypes + [UpperCase(TypeText)];
              end;
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
          begin
            Member.TypeName := CollapseSpace(NodeText(TypeRef));
          end;
          Parameters := Child.FindChild(TSyntaxKind.Parameters);
          if Parameters <> nil then
          begin
            Head := NodeText(Parameters);
            Member.Parameters := CollapseSpace(Copy(Head, 2, Length(Head) - 2));
          end;
          // Spezifizierer erst hinter dem Typ suchen, damit Parameternamen wie "Index" nicht stören.
          TokenRange(Child.StartOffset, Child.EndOffset, First, Last);
          if TypeRef <> nil then
          begin
            TokenRange(TypeRef.EndOffset, Child.EndOffset, First, Last);
          end;
          if First >= 0 then
          begin
            Member.ReadAccessor := SpecifierAfter(FTree.Tokens, First, Last, 'read');
            Member.WriteAccessor := SpecifierAfter(FTree.Tokens, First, Last, 'write');
            Member.IndexSpecifier := SpecifierAfter(FTree.Tokens, First, Last, 'index');
            Member.StoredSpecifier := SpecifierAfter(FTree.Tokens, First, Last, 'stored');
            // "; default;" hinter dem Semikolon der Deklaration.
            for Part := First to Last - 1 do
            begin
              if FTree.Tokens[Part].IsSymbol(';') then
              begin
                Next := Part + 1;
                while (Next <= Last) and IsTrivia(FTree.Tokens[Next]) do
                begin
                  Inc(Next);
                end;
                Member.IsDefaultArray := (Next <= Last) and SameText(FTree.Tokens[Next].Text, 'default');
                Break;
              end;
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
    begin
      for Position := 0 to High(A) do
      begin
        if not SameText(A[Position], B[Position]) then
        begin
          Exit(False);
        end;
      end;
    end;
  end;

begin
  Prefix := Decl.EnclosingTypeName;
  if Prefix = '' then
  begin
    Prefix := Name;
  end;
  Routines := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(Prefix + '.', ANode.Name) and
        (Pos('.', Copy(ANode.Name, Length(Prefix) + 2, MaxInt)) = 0) then
      begin
        Routines := Routines + [ANode];
      end;
    end);
  for Index := 0 to High(Members) do
  begin
    if not Members[Index].IsMethod and (Members[Index].Kind <> TClassMemberKind.Other) then
    begin
      Continue;
    end;
    if (Members[Index].Kind = TClassMemberKind.Other) and (Members[Index].Node.Kind <> TSyntaxKind.RoutineHeader) then
    begin
      Continue;
    end;
    Overloaded := False;
    for Other := 0 to High(Members) do
    begin
      if (Other <> Index) and Members[Other].IsMethod and SameText(Members[Other].Name, Members[Index].Name) then
      begin
        Overloaded := True;
      end;
    end;
    for Routine in Routines do
    begin
      if not SameText(Routine.Name, Prefix + '.' + Members[Index].Name) then
      begin
        Continue;
      end;
      if Overloaded then
      begin
        Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
        Types := nil;
        Parameters := nil;
        if Header <> nil then
        begin
          Parameters := Header.FindChild(TSyntaxKind.Parameters);
        end;
        if Parameters <> nil then
        begin
          for Other := 0 to Parameters.ChildCount - 1 do
          begin
            Parameter := Parameters[Other];
            TypeRef := Parameter.FindChild(TSyntaxKind.TypeReference);
            if TypeRef = nil then
            begin
              TypeRef := Parameter.FindChild(TSyntaxKind.ArrayType);
            end;
            for Names in Parameter.Name.Split([',']) do
            begin
              if TypeRef <> nil then
              begin
                Types := Types + [UpperCase(CollapseSpace(NodeText(TypeRef)))];
              end
              else
              begin
                Types := Types + [''];
              end;
            end;
          end;
        end;
        if not SameTypes(Types, Members[Index].ParameterTypes) then
        begin
          Continue;
        end;
      end;
      Members[Index].Body := Routine;
      Members[Index].BodyFirstLine := Routine.StartPos.Line;
      Doc := DocStart(Routine.StartPos.Line);
      if Doc >= 0 then
      begin
        Members[Index].BodyFirstLine := Doc;
      end;
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
  begin
    if SameText(Members[Index].Name, AName) then
    begin
      Result := Result + [Index];
    end;
  end;
end;

function TClassLayout.MemberAtLine(ALine: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(Members) do
  begin
    if (ALine >= Members[Index].FirstLine) and (ALine <= Members[Index].LastLine) and
      (Members[Index].Kind <> TClassMemberKind.Other) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

/// <summary>Bezeichner im Offsetbereich, die als Mitglied der eigenen Klasse gemeint sein können: ohne Punkt
/// davor oder hinter Self.</summary>
function MemberNames(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<string>;
var
  Index, Previous, Before: Integer;
begin
  Result := nil;
  for Index := TSyntaxTree.FirstTokenOf(ATokens, AFirst) to High(ATokens) do
  begin
    if ATokens[Index].Offset < AFirst then
    begin
      Continue;
    end;
    if ATokens[Index].Offset >= ALast then
    begin
      Break;
    end;
    if ATokens[Index].Kind <> TPascalTokenKind.Identifier then
    begin
      Continue;
    end;
    Previous := Index - 1;
    while (Previous >= 0) and IsTrivia(ATokens[Previous]) do
    begin
      Dec(Previous);
    end;
    if (Previous >= 0) and ATokens[Previous].IsSymbol('.') then
    begin
      Before := Previous - 1;
      while (Before >= 0) and IsTrivia(ATokens[Before]) do
      begin
        Dec(Before);
      end;
      if (Before < 0) or not SameText(ATokens[Before].Text, 'Self') then
      begin
        Continue;
      end;
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
  begin
    Names := MemberNames(FTree.Tokens, Member.Node.StartOffset, Member.Node.EndOffset);
  end;
  Body := Member.Body;
  if Body <> nil then
  begin
    // Ohne den Kopf: dessen Name ist kein Aufruf.
    Start := Body.StartOffset;
    if Body.FindChild(TSyntaxKind.RoutineHeader) <> nil then
    begin
      Start := Body.FindChild(TSyntaxKind.RoutineHeader).EndOffset;
    end;
    Names := Names + MemberNames(FTree.Tokens, Start, Body.EndOffset);
  end;
  Result := nil;
  for Index := 0 to High(Members) do
  begin
    if (Index = AIndex) or (Members[Index].Kind = TClassMemberKind.Other) then
    begin
      Continue;
    end;
    for Other := 0 to High(Names) do
    begin
      if SameText(Names[Other], Members[Index].Name) then
      begin
        Result := Result + [Index];
        Break;
      end;
    end;
  end;
  // Der Name der Property selbst ist keine Verwendung.
  if Member.Kind = TClassMemberKind.Property_ then
  begin
    for Index := High(Result) downto 0 do
    begin
      if SameText(Members[Result[Index]].Name, Member.Name) then
      begin
        Delete(Result, Index, 1);
      end;
    end;
  end;
end;

function TClassLayout.UsersOf(AIndex: Integer): TArray<Integer>;
var
  Index, Used: Integer;
begin
  Result := nil;
  for Index := 0 to High(Members) do
  begin
    if (Index = AIndex) or (Members[Index].Kind = TClassMemberKind.Other) then
    begin
      Continue;
    end;
    for Used in UsedBy(Index) do
    begin
      if SameText(Members[Used].Name, Members[AIndex].Name) then
      begin
        Result := Result + [Index];
        Break;
      end;
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
    begin
      Result := 'class var ' + Result;
    end;
    Exit;
  end;
  Result := CollapseSpace(NodeText(Member.Node));
  if Member.IsClassMember and (Member.Kind = TClassMemberKind.Property_) then
  begin
    Result := 'class ' + Result;
  end;
  if not Result.EndsWith(';') then
  begin
    Result := Result + ';';
  end;
end;

function TClassLayout.DocLines(AIndex: Integer): TArray<string>;
var
  Line, Stop: Integer;
begin
  Result := nil;
  if Members[AIndex].DocLine < 0 then
  begin
    Exit;
  end;
  Stop := Members[AIndex].Node.StartPos.Line - 1;
  for Line := Members[AIndex].DocLine to Stop do
  begin
    if StartsText('///', Trim(FLines[Line])) then
    begin
      Result := Result + [Trim(FLines[Line])];
    end;
  end;
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
  begin
    Exit(Declaration(AIndex));
  end;
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
  begin
    Result := Result + ';';
  end;
end;

function TClassLayout.LinesText(AFirst, ALast: Integer): string;
var
  Line: Integer;
begin
  Result := '';
  for Line := AFirst to ALast do
  begin
    Result := Result + FLines[Line] + LineBreak;
  end;
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
  begin
    Result := TClassVisibility.StrictPrivate;
  end
  else if Name = 'private' then
  begin
    Result := TClassVisibility.Private_;
  end
  else if Name = 'strict protected' then
  begin
    Result := TClassVisibility.StrictProtected;
  end
  else if Name = 'protected' then
  begin
    Result := TClassVisibility.Protected_;
  end
  else if Name = 'published' then
  begin
    Result := TClassVisibility.Published_;
  end
  else
  begin
    Result := TClassVisibility.Public_;
  end;
end;

class function TClassEdits.DeleteLines(ALayout: TClassLayout; AFirst, ALast: Integer): TTextEdit;
var
  Lines: TArray<string>;
begin
  Lines := ALayout.Lines;
  // Eine Leerzeile dahinter mitnehmen, wenn davor auch eine steht (Rümpfe sind durch Leerzeilen getrennt).
  if (ALast + 1 <= High(Lines)) and (Trim(Lines[ALast + 1]) = '') and (AFirst > 0) and
    (Trim(Lines[AFirst - 1]) = '') then
  begin
    Inc(ALast);
  end;
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
    begin
      if Done[Other] = Node then
      begin
        Dropped := True;
      end;
    end;
    if Dropped then
    begin
      Continue;
    end;
    Done := Done + [Node];
    if Member.IsFieldGroup then
    begin
      // Übrige Namen der Gruppe behalten.
      Remaining := nil;
      for Name in Member.GroupNames do
      begin
        Dropped := False;
        for Other in AIndexes do
        begin
          if (ALayout.Members[Other].Node = Node) and SameText(ALayout.Members[Other].Name, Name) then
          begin
            Dropped := True;
          end;
        end;
        if not Dropped then
        begin
          Remaining := Remaining + [Name];
        end;
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
    begin
      // Einziger Eintrag eines var-Abschnitts: der ganze Abschnitt samt "class var".
      Result := Result + [TTextEdit.Create(TTextRange.Create(Node.Parent.StartPos.Line, 0, Member.LastLine + 1, 0),
        '')];
    end
    else
    begin
      Result := Result + [TTextEdit.Create(TTextRange.Create(Member.FirstLine, 0, Member.LastLine + 1, 0), '')];
    end;
    if ABodies and (Member.Body <> nil) then
    begin
      Result := Result + [DeleteLines(ALayout, Member.BodyFirstLine, Member.BodyLastLine)];
    end;
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
  begin
    for Part in Item.Split([#10]) do
    begin
      Body := Body + ALayout.MemberIndent + TrimRight(Part) + ALayout.LineBreak;
    end;
  end;
  Found := -1;
  for Index := 0 to High(ALayout.Sections) do
  begin
    if (ALayout.Sections[Index].Visibility = AVisibility) and
      ((ALayout.Sections[Index].HeadLine >= 0) or (AVisibility = TClassVisibility.Public_)) then
    begin
      Found := Index;
    end;
  end;
  if Found < 0 then
  begin
    // Neuer Abschnitt in der Reihenfolge der Sichtbarkeit: vor den ersten mit höherer, sonst vor end.
    Line := ALayout.EndLine;
    for Index := High(ALayout.Sections) downto 0 do
    begin
      if (ALayout.Sections[Index].HeadLine >= 0) and (ALayout.Sections[Index].Visibility > AVisibility) then
      begin
        Line := ALayout.Sections[Index].HeadLine;
      end;
    end;
    Result := InsertBeforeLine(Line, ALayout.Indent + VisibilityName(AVisibility) +
      ALayout.LineBreak + Body);
    Exit;
  end;
  Section := ALayout.Sections[Found];
  if AFields then
  begin
    for Index in Section.Members do
    begin
      Member := ALayout.Members[Index];
      if Member.IsMethod or (Member.Kind = TClassMemberKind.Property_) then
      begin
        Exit(InsertBeforeLine(Member.FirstLine, Body));
      end;
    end;
  end;
  // Hinter das letzte Mitglied bzw. die Kopfzeile des Abschnitts.
  Line := Section.HeadLine;
  if Line < 0 then
  begin
    Line := ALayout.HeaderLine;
  end;
  for Index in Section.Members do
  begin
    if ALayout.Members[Index].LastLine > Line then
    begin
      Line := ALayout.Members[Index].LastLine;
    end;
  end;
  Result := InsertBeforeLine(Line + 1, Body);
end;

class function TClassEdits.SetAncestors(ALayout: TClassLayout; const AAncestors: TArray<string>): TTextEdit;
var
  Table: TLineTable;
  List: string;
begin
  Table := TLineTable.Build(ALayout.Text);
  List := '';
  if AAncestors <> nil then
  begin
    List := '(' + string.Join(', ', AAncestors) + ')';
  end;
  if ALayout.HeritageOpen >= 0 then
  begin
    Result := TTextEdit.Create(TTextRange.Create(Table.PositionAt(ALayout.HeritageOpen),
      Table.PositionAt(ALayout.HeritageClose + 1)), List);
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(Table.PositionAt(ALayout.HeritageInsert),
      Table.PositionAt(ALayout.HeritageInsert)), List);
  end;
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
  begin
    Exit('');
  end;
  Table := TLineTable.Build(ALayout.Text);
  Start := Table.LineStart(Member.BodyFirstLine);
  Text := Copy(ALayout.Text, Start + 1, Member.Body.EndOffset - Start);
  // Klassenname im Kopf ersetzen: erster Bezeichner mit dem Namen der Klasse (Typparameter bleiben).
  Tokens := ALayout.Tree.Tokens;
  for Index := TokenIndexAt(Tokens, Member.Body.StartOffset) to High(Tokens) do
  begin
    if Tokens[Index].IsSymbol('(') or Tokens[Index].IsSymbol(';') then
    begin
      Break;
    end;
    if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, ALayout.Name) then
    begin
      Offset := Tokens[Index].Offset - Start;
      Text := Copy(Text, 1, Offset) + AClassName + Copy(Text, Offset + Length(Tokens[Index].Text) + 1, MaxInt);
      Break;
    end;
  end;
  Result := Text;
end;

class function TClassEdits.BodiesEnd(ATree: TSyntaxTree; const AClassName: string): Integer;
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
      begin
        Implementation_ := ANode;
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(AClassName + '.', ANode.Name) and (ANode.EndPos.Line > Last) then
      begin
        Last := ANode.EndPos.Line;
      end;
    end);
  if Last >= 0 then
  begin
    Exit(Last);
  end;
  if Implementation_ = nil then
  begin
    Exit(-1);
  end;
  // Hinter die letzte Deklaration der implementation, sonst hinter "implementation" bzw. dessen uses.
  Result := Implementation_.StartPos.Line;
  for Index := 0 to Implementation_.ChildCount - 1 do
  begin
    if Implementation_[Index].EndPos.Line > Result then
    begin
      Result := Implementation_[Index].EndPos.Line;
    end;
  end;
end;

class function TClassEdits.InsertBodies(const AText: string; ALine: Integer;
  const ABodies: TArray<string>): TTextEdit;
var
  LineBreak, Body, NewText: string;
begin
  LineBreak := TTextLines.LineBreakOf(AText);
  NewText := '';
  for Body in ABodies do
  begin
    NewText := NewText + LineBreak + Body + LineBreak;
  end;
  Result := InsertBeforeLine(ALine + 1, NewText);
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
  begin
    Start := TypeRef.EndOffset;
  end;
  Tokens := ALayout.Tree.Tokens;
  Index := TokenIndexAt(Tokens, Start);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) and not Tokens[Index].IsSymbol(';') do
  begin
    if (Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
      SameText(Tokens[Index].Text, AKeyword) then
    begin
      Next := Index + 1;
      while (Next <= High(Tokens)) and IsTrivia(Tokens[Next]) do
      begin
        Inc(Next);
      end;
      if (Next > High(Tokens)) or (Tokens[Next].Kind <> TPascalTokenKind.Identifier) then
      begin
        Exit(False);
      end;
      AEdit := TTextEdit.Create(TTextRange.Create(Tokens[Next].StartPos, Tokens[Next].EndPos), ANewName);
      Exit(True);
    end;
    Inc(Index);
  end;
  Result := False;
end;

class function TClassEdits.InsertBeforeLine(ALine: Integer; const ANewText: string): TTextEdit;
begin
  Result := TTextEdit.Create(TTextRange.Create(ALine, 0, ALine, 0), ANewText);
end;

end.
