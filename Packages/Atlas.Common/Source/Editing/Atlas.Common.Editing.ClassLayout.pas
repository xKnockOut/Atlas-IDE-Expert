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

  /// <summary>Klasse auf der Kopfzeile Line einer Unit mit Text und Syntaxbaum.</summary>
  TClassSource = record
    Tree: TSyntaxTree;
    Text: string;
    Line: Integer;
    class function Create(ATree: TSyntaxTree; const AText: string; ALine: Integer): TClassSource; static;
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

type
  /// <summary>Liest Kopf, Mitglieder und Rümpfe einer Klassendeklaration in ein TClassLayout.</summary>
  TClassLayoutReader = record
  private
    FLayout: TClassLayout;
    FTokens: TArray<TPascalToken>;
    /// <summary>Sichtbarkeit und Abschnitt, in dem das nächste Mitglied steht.</summary>
    FVisibility: TClassVisibility;
    FSection: TClassSection;
    /// <summary>Zeile des ersten Attributs vor dem nächsten Mitglied; -1 ohne.</summary>
    FPending: Integer;
    function NodeText(ANode: TSyntaxNode): string;
    function CollapsedText(ANode: TSyntaxNode): string;
    function InnerText(ANode: TSyntaxNode): string;
    function DocStart(ALine: Integer): Integer;
    function TokenRange(AFirstOffset, ALastOffset: Integer; out AFirst, ALast: Integer): Boolean;
    function AfterClass(AOffset: Integer): Boolean;
    function SkipTrivia(AIndex, ALast: Integer): Integer;
    function ClosingParen(AOpen, ALast: Integer): Integer;
    function FirstAttribute: TSyntaxNode;
    function IsInInterface: Boolean;
    procedure ReadAncestors;
    procedure ReadHeritage;
    procedure ReadHeader;
    function NewMember(AKind: TClassMemberKind; ANode: TSyntaxNode; const AName: string): TClassMember;
    procedure Add(const AMember: TClassMember);
    procedure StartSection(AChild: TSyntaxNode);
    procedure ReadField(AChild: TSyntaxNode);
    procedure ReadVarDecl(AInner: TSyntaxNode; AIsClass: Boolean);
    procedure ReadVarSection(AChild: TSyntaxNode);
    function ParameterTypes(AParameters: TSyntaxNode): TArray<string>;
    procedure ReadRoutineParts(var AMember: TClassMember; AChild: TSyntaxNode);
    procedure ReadRoutine(AChild: TSyntaxNode);
    procedure ReadSpecifiers(var AMember: TClassMember; AFirst, ALast: Integer);
    procedure ReadProperty(AChild: TSyntaxNode);
    procedure ReadChild(AChild: TSyntaxNode);
    procedure ReadMembers;
    function Routines(const APrefix: string): TArray<TSyntaxNode>;
    function NeedsBody(AIndex: Integer): Boolean;
    function IsOverloaded(AIndex: Integer): Boolean;
    function BodyTypes(ARoutine: TSyntaxNode): TArray<string>;
    procedure SetBody(AIndex: Integer; ARoutine: TSyntaxNode);
    procedure FindBody(AIndex: Integer; const APrefix: string; const ARoutines: TArray<TSyntaxNode>);
    procedure FindBodies;
  public
    class procedure Run(ALayout: TClassLayout); static;
  end;

{ TClassSource }

class function TClassSource.Create(ATree: TSyntaxTree; const AText: string; ALine: Integer): TClassSource;
begin
  Result.Tree := ATree;
  Result.Text := AText;
  Result.Line := ALine;
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
    TClassLayoutReader.Run(Result);
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

function TClassLayout.TextOf(ANode: TSyntaxNode): string;
begin
  Result := Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

{ TClassLayoutReader }

class procedure TClassLayoutReader.Run(ALayout: TClassLayout);
var
  mReader: TClassLayoutReader;
begin
  mReader := Default(TClassLayoutReader);
  mReader.FLayout := ALayout;
  mReader.FTokens := ALayout.FTree.Tokens;
  mReader.ReadHeader;
  mReader.ReadMembers;
  mReader.FindBodies;
end;

function TClassLayoutReader.NodeText(ANode: TSyntaxNode): string;
begin
  Result := FLayout.TextOf(ANode);
end;

function TClassLayoutReader.CollapsedText(ANode: TSyntaxNode): string;
begin
  Result := CollapseSpace(NodeText(ANode));
end;

/// <summary>Text eines Knotens ohne das erste und letzte Zeichen (Klammern), Leerraum zusammengefasst.</summary>
function TClassLayoutReader.InnerText(ANode: TSyntaxNode): string;
var
  mText: string;
begin
  mText := NodeText(ANode);
  Result := CollapseSpace(Copy(mText, 2, Length(mText) - 2));
end;

function TClassLayoutReader.TokenRange(AFirstOffset, ALastOffset: Integer; out AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  AFirst := -1;
  ALast := -1;
  mIndex := TokenIndexAt(FTokens, AFirstOffset);
  while (mIndex <= High(FTokens)) and (FTokens[mIndex].Offset < ALastOffset) do
  begin
    if AFirst < 0 then
    begin
      AFirst := mIndex;
    end;
    ALast := mIndex;
    Inc(mIndex);
  end;
  Result := AFirst >= 0;
end;

function TClassLayoutReader.AfterClass(AOffset: Integer): Boolean;
var
  mIndex: Integer;
begin
  mIndex := TokenIndexAt(FTokens, AOffset) - 1;
  while (mIndex >= 0) and IsTrivia(FTokens[mIndex]) do
  begin
    Dec(mIndex);
  end;
  Result := (mIndex >= 0) and FTokens[mIndex].IsKeyword('class');
end;

function TClassLayoutReader.DocStart(ALine: Integer): Integer;
begin
  Result := -1;
  while (ALine > 0) and StartsText('///', Trim(FLayout.FLines[ALine - 1])) do
  begin
    Dec(ALine);
    Result := ALine;
  end;
end;

/// <summary>Erstes Token ab AIndex, das kein Kommentar und keine Direktive ist; ALast + 1 ohne.</summary>
function TClassLayoutReader.SkipTrivia(AIndex, ALast: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= ALast) and IsTrivia(FTokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Offset der Klammer, die die Klammer am Token AOpen schließt; -1 ohne bis ALast.</summary>
function TClassLayoutReader.ClosingParen(AOpen, ALast: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := -1;
  mDepth := 0;
  mIndex := AOpen;
  while (mIndex <= ALast) and (Result < 0) do
  begin
    if FTokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if FTokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Result := FTokens[mIndex].Offset;
      end;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Erstes der Attribute, die als Geschwister direkt vor der Deklaration stehen; nil ohne.</summary>
function TClassLayoutReader.FirstAttribute: TSyntaxNode;
var
  mParent: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mParent := FLayout.Decl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  mIndex := 0;
  while (mIndex < mParent.ChildCount) and (mParent[mIndex] <> FLayout.Decl) do
  begin
    Inc(mIndex);
  end;
  if mIndex >= mParent.ChildCount then
  begin
    Exit;
  end;
  Dec(mIndex);
  while (mIndex >= 0) and (mParent[mIndex].Kind = TSyntaxKind.Attribute) do
  begin
    Result := mParent[mIndex];
    Dec(mIndex);
  end;
end;

function TClassLayoutReader.IsInInterface: Boolean;
var
  mNode: TSyntaxNode;
begin
  Result := False;
  mNode := FLayout.Decl.Parent;
  while (mNode <> nil) and not Result do
  begin
    Result := mNode.Kind = TSyntaxKind.InterfaceSection;
    mNode := mNode.Parent;
  end;
end;

procedure TClassLayoutReader.ReadAncestors;
var
  mIndex: Integer;
  mClass: TSyntaxNode;
begin
  mClass := FLayout.ClassNode;
  FLayout.Ancestors := nil;
  mIndex := 0;
  while (mIndex < mClass.ChildCount) and (mClass[mIndex].Kind = TSyntaxKind.TypeReference) do
  begin
    FLayout.Ancestors := FLayout.Ancestors + [CollapsedText(mClass[mIndex])];
    Inc(mIndex);
  end;
end;

/// <summary>Klammern der Vorfahrenliste und Stelle hinter class [abstract|sealed].</summary>
procedure TClassLayoutReader.ReadHeritage;
var
  mFirst, mLast, mIndex: Integer;
  mClass: TSyntaxNode;
begin
  mClass := FLayout.ClassNode;
  FLayout.HeritageOpen := -1;
  FLayout.HeritageClose := -1;
  FLayout.HeritageInsert := mClass.StartOffset + Length('class');
  if not TokenRange(mClass.StartOffset, mClass.EndOffset, mFirst, mLast) then
  begin
    Exit;
  end;
  mIndex := SkipTrivia(mFirst + 1, mLast);
  if (mIndex <= mLast) and (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    MatchText(FTokens[mIndex].Text, ['abstract', 'sealed']) then
  begin
    FLayout.HeritageInsert := FTokens[mIndex].Offset + Length(FTokens[mIndex].Text);
    mIndex := SkipTrivia(mIndex + 1, mLast);
  end;
  if (mIndex <= mLast) and FTokens[mIndex].IsSymbol('(') then
  begin
    FLayout.HeritageOpen := FTokens[mIndex].Offset;
    FLayout.HeritageClose := ClosingParen(mIndex, mLast);
  end;
end;

procedure TClassLayoutReader.ReadHeader;
var
  mAttribute, mParams: TSyntaxNode;
  mDoc: Integer;
begin
  FLayout.HeaderLine := FLayout.Decl.StartPos.Line;
  FLayout.FirstLine := FLayout.HeaderLine;
  mAttribute := FirstAttribute;
  if mAttribute <> nil then
  begin
    FLayout.FirstLine := mAttribute.StartPos.Line;
  end;
  mDoc := DocStart(FLayout.FirstLine);
  if mDoc >= 0 then
  begin
    FLayout.FirstLine := mDoc;
  end;
  FLayout.Indent := TTextLines.IndentOf(FLayout.FLines[FLayout.HeaderLine]);
  FLayout.MemberIndent := FLayout.Indent + '  ';
  FLayout.EndLine := FLayout.ClassNode.EndPos.Line;
  FLayout.InInterface := IsInInterface;
  mParams := FLayout.Decl.FindChild(TSyntaxKind.GenericParams);
  if mParams <> nil then
  begin
    FLayout.GenericParams := CollapsedText(mParams);
  end;
  ReadAncestors;
  ReadHeritage;
end;

const
  PropertySpecifiers: array[0..7] of string = ('read', 'write', 'index', 'stored', 'default', 'nodefault',
    'implements', 'dispid');

/// <summary>Token AIndex ist ein Spezifizierer einer Property (read, write, …).</summary>
function IsSpecifier(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    MatchText(AToken.Text, PropertySpecifiers);
end;

/// <summary>Text der Token ab AIndex bis vor den nächsten Spezifizierer bzw. das Semikolon, ohne Kommentare.
/// </summary>
function SpecifierValue(const ATokens: TArray<TPascalToken>; AIndex, ALast: Integer): string;
begin
  Result := '';
  while (AIndex <= ALast) and not ATokens[AIndex].IsSymbol(';') and not IsSpecifier(ATokens[AIndex]) do
  begin
    if not IsTrivia(ATokens[AIndex]) then
    begin
      Result := Result + ATokens[AIndex].Text;
    end;
    Inc(AIndex);
  end;
end;

/// <summary>Wert hinter dem Spezifizierer AKeyword einer Property zwischen den Token AFirst und ALast (bis zum
/// nächsten Spezifizierer bzw. Semikolon); '' ohne.</summary>
function SpecifierAfter(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer; const AKeyword: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := AFirst;
  while (mIndex <= ALast) and not ATokens[mIndex].IsSymbol(';') do
  begin
    if not IsTrivia(ATokens[mIndex]) and (ATokens[mIndex].Kind in [TPascalTokenKind.Identifier,
      TPascalTokenKind.Keyword]) and SameText(ATokens[mIndex].Text, AKeyword) then
    begin
      Exit(SpecifierValue(ATokens, mIndex + 1, ALast));
    end;
    Inc(mIndex);
  end;
end;

/// <summary>"; default;" hinter dem Semikolon der Deklaration zwischen den Token AFirst und ALast.</summary>
function IsDefaultArray(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := AFirst;
  while (mIndex < ALast) and not ATokens[mIndex].IsSymbol(';') do
  begin
    Inc(mIndex);
  end;
  if mIndex < ALast then
  begin
    Inc(mIndex);
    while (mIndex <= ALast) and IsTrivia(ATokens[mIndex]) do
    begin
      Inc(mIndex);
    end;
    Result := (mIndex <= ALast) and SameText(ATokens[mIndex].Text, 'default');
  end;
end;

/// <summary>Namen einer Gruppe ("FA, FB") einzeln, ohne Leerraum am Rand.</summary>
function SplitNames(const AText: string): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in AText.Split([',']) do
  begin
    Result := Result + [Trim(mName)];
  end;
end;

/// <summary>Art einer Routine nach ihrem Schlüsselwort (ohne "class" davor).</summary>
function RoutineKind(const AHead: string): TClassMemberKind;
begin
  Result := TClassMemberKind.Method;
  if StartsText('constructor', AHead) then
  begin
    Result := TClassMemberKind.Constructor_;
  end
  else if StartsText('destructor', AHead) then
  begin
    Result := TClassMemberKind.Destructor_;
  end
  else if StartsText('operator', AHead) then
  begin
    Result := TClassMemberKind.Other;
  end;
end;

function SameTypes(const A, B: TArray<string>): Boolean;
var
  mPosition: Integer;
begin
  Result := Length(A) = Length(B);
  mPosition := 0;
  while Result and (mPosition <= High(A)) do
  begin
    Result := SameText(A[mPosition], B[mPosition]);
    Inc(mPosition);
  end;
end;

function TClassLayoutReader.NewMember(AKind: TClassMemberKind; ANode: TSyntaxNode; const AName: string): TClassMember;
begin
  Result := Default(TClassMember);
  Result.Kind := AKind;
  Result.Node := ANode;
  Result.Name := AName;
  Result.GroupNames := [AName];
  Result.Visibility := FVisibility;
  Result.FirstLine := ANode.StartPos.Line;
  if FPending >= 0 then
  begin
    Result.FirstLine := FPending;
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

procedure TClassLayoutReader.Add(const AMember: TClassMember);
begin
  FLayout.Members := FLayout.Members + [AMember];
  FSection.Members := FSection.Members + [High(FLayout.Members)];
end;

procedure TClassLayoutReader.StartSection(AChild: TSyntaxNode);
begin
  if (FSection.HeadLine >= 0) or (FSection.Members <> nil) then
  begin
    FLayout.Sections := FLayout.Sections + [FSection];
  end;
  FVisibility := TClassEdits.VisibilityOf(AChild.Name);
  FSection := Default(TClassSection);
  FSection.Visibility := FVisibility;
  FSection.HeadLine := AChild.StartPos.Line;
end;

procedure TClassLayoutReader.ReadField(AChild: TSyntaxNode);
var
  mNames: TArray<string>;
  mName, mTypeText: string;
  mTypeRef: TSyntaxNode;
  mMember: TClassMember;
begin
  mNames := SplitNames(AChild.Name);
  mTypeText := '';
  mTypeRef := AChild.FindChild(TSyntaxKind.TypeReference);
  if mTypeRef <> nil then
  begin
    mTypeText := CollapsedText(mTypeRef);
  end
  else if AChild.ChildCount > 0 then
  begin
    mTypeText := CollapsedText(AChild[0]);
  end;
  for mName in mNames do
  begin
    mMember := NewMember(TClassMemberKind.Field, AChild, mName);
    mMember.GroupNames := mNames;
    mMember.TypeName := mTypeText;
    Add(mMember);
  end;
end;

procedure TClassLayoutReader.ReadVarDecl(AInner: TSyntaxNode; AIsClass: Boolean);
var
  mNames: TArray<string>;
  mName: string;
  mTypeRef: TSyntaxNode;
  mKind: TClassMemberKind;
  mMember: TClassMember;
begin
  mNames := SplitNames(AInner.Name);
  mTypeRef := AInner.FindChild(TSyntaxKind.TypeReference);
  mKind := TClassMemberKind.Field;
  if AIsClass then
  begin
    mKind := TClassMemberKind.ClassVar;
  end;
  for mName in mNames do
  begin
    mMember := NewMember(mKind, AInner, mName);
    mMember.GroupNames := mNames;
    mMember.IsClassMember := AIsClass;
    if mTypeRef <> nil then
    begin
      mMember.TypeName := CollapsedText(mTypeRef);
    end;
    Add(mMember);
  end;
end;

/// <summary>class var bzw. var-Abschnitt in der Klasse: je Name ein Mitglied.</summary>
procedure TClassLayoutReader.ReadVarSection(AChild: TSyntaxNode);
var
  mIndex: Integer;
  mIsClass: Boolean;
begin
  mIsClass := AfterClass(AChild.StartOffset);
  for mIndex := 0 to AChild.ChildCount - 1 do
  begin
    if AChild[mIndex].Kind = TSyntaxKind.VarDecl then
    begin
      ReadVarDecl(AChild[mIndex], mIsClass);
    end;
  end;
end;

/// <summary>Typen der Parameter in Reihenfolge, je Name einer Gruppe einer, in Großschreibung; '' ohne Typ.
/// </summary>
function TClassLayoutReader.ParameterTypes(AParameters: TSyntaxNode): TArray<string>;
var
  mIndex, mCount: Integer;
  mParameter, mTypeRef: TSyntaxNode;
  mTypeText: string;
begin
  Result := nil;
  for mIndex := 0 to AParameters.ChildCount - 1 do
  begin
    mParameter := AParameters[mIndex];
    mTypeRef := mParameter.FindChild(TSyntaxKind.TypeReference);
    if mTypeRef = nil then
    begin
      mTypeRef := mParameter.FindChild(TSyntaxKind.ArrayType);
    end;
    mTypeText := '';
    if mTypeRef <> nil then
    begin
      mTypeText := UpperCase(CollapsedText(mTypeRef));
    end;
    for mCount := 1 to Length(mParameter.Name.Split([','])) do
    begin
      Result := Result + [mTypeText];
    end;
  end;
end;

/// <summary>Ergebnistyp und Direktiven einer Routine.</summary>
procedure TClassLayoutReader.ReadRoutineParts(var AMember: TClassMember; AChild: TSyntaxNode);
var
  mIndex: Integer;
  mInner: TSyntaxNode;
begin
  for mIndex := 0 to AChild.ChildCount - 1 do
  begin
    mInner := AChild[mIndex];
    if mInner.Kind = TSyntaxKind.TypeReference then
    begin
      AMember.TypeName := CollapsedText(mInner);
    end
    else if mInner.Kind = TSyntaxKind.Directive then
    begin
      AMember.Directives := AMember.Directives + [mInner.Name];
    end;
  end;
end;

procedure TClassLayoutReader.ReadRoutine(AChild: TSyntaxNode);
var
  mHead: string;
  mMember: TClassMember;
  mParameters: TSyntaxNode;
begin
  if AChild.IsMethodResolution then
  begin
    Exit;
  end;
  mHead := TrimLeft(Copy(FLayout.FText, AChild.StartOffset + 1, 40));
  mMember := NewMember(TClassMemberKind.Method, AChild, AChild.Name);
  mMember.IsClassMember := StartsText('class', mHead) and (Length(mHead) > 5) and not mHead[6].IsLetterOrDigit;
  if mMember.IsClassMember then
  begin
    mHead := TrimLeft(Copy(mHead, 6, MaxInt));
  end;
  mMember.Kind := RoutineKind(mHead);
  mMember.IsGeneric := AChild.FindChild(TSyntaxKind.GenericParams) <> nil;
  ReadRoutineParts(mMember, AChild);
  mParameters := AChild.FindChild(TSyntaxKind.Parameters);
  if mParameters <> nil then
  begin
    mMember.Parameters := InnerText(mParameters);
    mMember.ParameterTypes := ParameterTypes(mParameters);
  end;
  Add(mMember);
end;

procedure TClassLayoutReader.ReadSpecifiers(var AMember: TClassMember; AFirst, ALast: Integer);
begin
  AMember.ReadAccessor := SpecifierAfter(FTokens, AFirst, ALast, 'read');
  AMember.WriteAccessor := SpecifierAfter(FTokens, AFirst, ALast, 'write');
  AMember.IndexSpecifier := SpecifierAfter(FTokens, AFirst, ALast, 'index');
  AMember.StoredSpecifier := SpecifierAfter(FTokens, AFirst, ALast, 'stored');
  AMember.IsDefaultArray := IsDefaultArray(FTokens, AFirst, ALast);
end;

procedure TClassLayoutReader.ReadProperty(AChild: TSyntaxNode);
var
  mMember: TClassMember;
  mTypeRef, mParameters: TSyntaxNode;
  mStart, mFirst, mLast: Integer;
begin
  mMember := NewMember(TClassMemberKind.Property_, AChild, AChild.Name);
  mMember.IsClassMember := AfterClass(AChild.StartOffset);
  mTypeRef := AChild.FindChild(TSyntaxKind.TypeReference);
  mMember.IsRedeclaration := mTypeRef = nil;
  mStart := AChild.StartOffset;
  if mTypeRef <> nil then
  begin
    mMember.TypeName := CollapsedText(mTypeRef);
    // Spezifizierer erst hinter dem Typ suchen, damit Parameternamen wie "Index" nicht stören.
    mStart := mTypeRef.EndOffset;
  end;
  mParameters := AChild.FindChild(TSyntaxKind.Parameters);
  if mParameters <> nil then
  begin
    mMember.Parameters := InnerText(mParameters);
  end;
  if TokenRange(mStart, AChild.EndOffset, mFirst, mLast) then
  begin
    ReadSpecifiers(mMember, mFirst, mLast);
  end;
  Add(mMember);
end;

procedure TClassLayoutReader.ReadChild(AChild: TSyntaxNode);
begin
  if AChild.Kind = TSyntaxKind.TypeReference then
  begin
    Exit;
  end;
  case AChild.Kind of
    TSyntaxKind.Visibility:
      StartSection(AChild);
    TSyntaxKind.Attribute:
      if FPending < 0 then
      begin
        FPending := AChild.StartPos.Line;
      end;
    TSyntaxKind.Field:
      ReadField(AChild);
    TSyntaxKind.VarSection:
      ReadVarSection(AChild);
    TSyntaxKind.RoutineHeader:
      ReadRoutine(AChild);
    TSyntaxKind.PropertyDecl:
      ReadProperty(AChild);
  else
    // Konstanten, verschachtelte Typen, variante Teile: zählen als Zeilen, sind aber keine Umbauziele.
    Add(NewMember(TClassMemberKind.Other, AChild, AChild.Name));
  end;
  if AChild.Kind <> TSyntaxKind.Attribute then
  begin
    FPending := -1;
  end;
end;

procedure TClassLayoutReader.ReadMembers;
var
  mIndex: Integer;
begin
  FLayout.Members := nil;
  FLayout.Sections := nil;
  FVisibility := TClassVisibility.Public_;
  FSection := Default(TClassSection);
  FSection.Visibility := FVisibility;
  FSection.HeadLine := -1;
  FPending := -1;
  for mIndex := 0 to FLayout.ClassNode.ChildCount - 1 do
  begin
    ReadChild(FLayout.ClassNode[mIndex]);
  end;
  FLayout.Sections := FLayout.Sections + [FSection];
end;

/// <summary>Routinen der Datei, deren Name APrefix.Methode lautet.</summary>
function TClassLayoutReader.Routines(const APrefix: string): TArray<TSyntaxNode>;
var
  mFound: TArray<TSyntaxNode>;
begin
  mFound := nil;
  FLayout.FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and StartsText(APrefix + '.', ANode.Name) and
        (Pos('.', Copy(ANode.Name, Length(APrefix) + 2, MaxInt)) = 0) then
      begin
        mFound := mFound + [ANode];
      end;
    end);
  Result := mFound;
end;

function TClassLayoutReader.NeedsBody(AIndex: Integer): Boolean;
var
  mMember: TClassMember;
begin
  mMember := FLayout.Members[AIndex];
  Result := mMember.IsMethod or (mMember.Kind = TClassMemberKind.Other) and
    (mMember.Node.Kind = TSyntaxKind.RoutineHeader);
end;

function TClassLayoutReader.IsOverloaded(AIndex: Integer): Boolean;
var
  mOther: Integer;
begin
  Result := False;
  mOther := 0;
  while not Result and (mOther <= High(FLayout.Members)) do
  begin
    Result := (mOther <> AIndex) and FLayout.Members[mOther].IsMethod and
      SameText(FLayout.Members[mOther].Name, FLayout.Members[AIndex].Name);
    Inc(mOther);
  end;
end;

/// <summary>Parametertypen im Kopf eines Rumpfs.</summary>
function TClassLayoutReader.BodyTypes(ARoutine: TSyntaxNode): TArray<string>;
var
  mHeader, mParameters: TSyntaxNode;
begin
  Result := nil;
  mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader = nil then
  begin
    Exit;
  end;
  mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
  if mParameters <> nil then
  begin
    Result := ParameterTypes(mParameters);
  end;
end;

procedure TClassLayoutReader.SetBody(AIndex: Integer; ARoutine: TSyntaxNode);
var
  mDoc: Integer;
begin
  FLayout.Members[AIndex].Body := ARoutine;
  FLayout.Members[AIndex].BodyFirstLine := ARoutine.StartPos.Line;
  mDoc := DocStart(ARoutine.StartPos.Line);
  if mDoc >= 0 then
  begin
    FLayout.Members[AIndex].BodyFirstLine := mDoc;
  end;
  FLayout.Members[AIndex].BodyLastLine := ARoutine.EndPos.Line;
end;

/// <summary>Rumpf des Mitglieds AIndex unter ARoutines; überladene Methoden über die Parametertypen.</summary>
procedure TClassLayoutReader.FindBody(AIndex: Integer; const APrefix: string; const ARoutines: TArray<TSyntaxNode>);
var
  mOverloaded: Boolean;
  mRoutine: TSyntaxNode;
begin
  mOverloaded := IsOverloaded(AIndex);
  for mRoutine in ARoutines do
  begin
    if SameText(mRoutine.Name, APrefix + '.' + FLayout.Members[AIndex].Name) and
      (not mOverloaded or SameTypes(BodyTypes(mRoutine), FLayout.Members[AIndex].ParameterTypes)) then
    begin
      SetBody(AIndex, mRoutine);
      Exit;
    end;
  end;
end;

procedure TClassLayoutReader.FindBodies;
var
  mPrefix: string;
  mRoutines: TArray<TSyntaxNode>;
  mIndex: Integer;
begin
  mPrefix := FLayout.Decl.EnclosingTypeName;
  if mPrefix = '' then
  begin
    mPrefix := FLayout.Name;
  end;
  mRoutines := Routines(mPrefix);
  for mIndex := 0 to High(FLayout.Members) do
  begin
    if NeedsBody(mIndex) then
    begin
      FindBody(mIndex, mPrefix, mRoutines);
    end;
  end;
end;

{ TClassLayout }

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

/// <summary>Index des letzten Tokens vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousSolid(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Der Bezeichner AIndex kann ein Mitglied der eigenen Klasse meinen: ohne Punkt davor oder hinter
/// Self.</summary>
function IsOwnMemberRef(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
var
  mPrevious, mBefore: Integer;
begin
  mPrevious := PreviousSolid(ATokens, AIndex);
  Result := (mPrevious < 0) or not ATokens[mPrevious].IsSymbol('.');
  if not Result then
  begin
    mBefore := PreviousSolid(ATokens, mPrevious);
    Result := (mBefore >= 0) and SameText(ATokens[mBefore].Text, 'Self');
  end;
end;

/// <summary>Bezeichner im Offsetbereich, die als Mitglied der eigenen Klasse gemeint sein können: ohne Punkt
/// davor oder hinter Self.</summary>
function MemberNames(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := TSyntaxTree.FirstTokenOf(ATokens, AFirst);
  while (mIndex <= High(ATokens)) and (ATokens[mIndex].Offset < ALast) do
  begin
    if (ATokens[mIndex].Offset >= AFirst) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      IsOwnMemberRef(ATokens, mIndex) then
    begin
      Result := Result + [ATokens[mIndex].Text];
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Namen, die AMember in Deklaration (nur Property-Zugriff) und Rumpf (ohne Kopf) benutzt.</summary>
function NamesUsedBy(const ATokens: TArray<TPascalToken>; const AMember: TClassMember): TArray<string>;
var
  mStart: Integer;
  mHeader: TSyntaxNode;
begin
  Result := nil;
  if AMember.Kind = TClassMemberKind.Property_ then
  begin
    Result := MemberNames(ATokens, AMember.Node.StartOffset, AMember.Node.EndOffset);
  end;
  if AMember.Body = nil then
  begin
    Exit;
  end;
  // Ohne den Kopf: dessen Name ist kein Aufruf.
  mStart := AMember.Body.StartOffset;
  mHeader := AMember.Body.FindChild(TSyntaxKind.RoutineHeader);
  if mHeader <> nil then
  begin
    mStart := mHeader.EndOffset;
  end;
  Result := Result + MemberNames(ATokens, mStart, AMember.Body.EndOffset);
end;

function TClassLayout.UsedBy(AIndex: Integer): TArray<Integer>;
var
  mNames: TArray<string>;
  mMember: TClassMember;
  mIndex: Integer;
begin
  mMember := Members[AIndex];
  mNames := NamesUsedBy(FTree.Tokens, mMember);
  Result := nil;
  for mIndex := 0 to High(Members) do
  begin
    // Der Name der Property selbst ist keine Verwendung.
    if (mIndex <> AIndex) and (Members[mIndex].Kind <> TClassMemberKind.Other) and
      (IndexText(Members[mIndex].Name, mNames) >= 0) and
      not ((mMember.Kind = TClassMemberKind.Property_) and SameText(Members[mIndex].Name, mMember.Name)) then
    begin
      Result := Result + [mIndex];
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
  Result := CollapseSpace(TextOf(Member.Node));
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

function NodeIn(const ANodes: TArray<TSyntaxNode>; ANode: TSyntaxNode): Boolean;
var
  mNode: TSyntaxNode;
begin
  for mNode in ANodes do
  begin
    if mNode = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Unter AIndexes steht ein Mitglied mit Knoten ANode und Namen AName.</summary>
function IsDropped(ALayout: TClassLayout; const AIndexes: TArray<Integer>; ANode: TSyntaxNode;
  const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex in AIndexes do
  begin
    if (ALayout.Members[mIndex].Node = ANode) and SameText(ALayout.Members[mIndex].Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Namen der Feldgruppe von AMember, die nicht unter AIndexes gelöscht werden.</summary>
function RemainingNames(ALayout: TClassLayout; const AIndexes: TArray<Integer>;
  const AMember: TClassMember): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in AMember.GroupNames do
  begin
    if not IsDropped(ALayout, AIndexes, AMember.Node, mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Deklaration der Feldgruppe von AMember durch die übrigen Namen ARemaining ersetzen.</summary>
function GroupEdit(ALayout: TClassLayout; const AMember: TClassMember; const ARemaining: TArray<string>): TTextEdit;
var
  mTable: TLineTable;
  mRange: TTextRange;
begin
  mTable := TLineTable.Build(ALayout.Text);
  mRange := TTextRange.Create(mTable.PositionAt(AMember.Node.StartOffset), mTable.PositionAt(AMember.Node.EndOffset));
  Result := TTextEdit.Create(mRange, string.Join(', ', ARemaining) + ': ' + AMember.TypeName + ';');
end;

/// <summary>Zeilen der Deklaration von AMember löschen; beim einzigen Eintrag eines var-Abschnitts den ganzen
/// Abschnitt samt "class var".</summary>
function DeclarationDelete(const AMember: TClassMember): TTextEdit;
var
  mNode: TSyntaxNode;
  mFirst: Integer;
begin
  mNode := AMember.Node;
  mFirst := AMember.FirstLine;
  if (mNode.Kind = TSyntaxKind.VarDecl) and (mNode.Parent <> nil) and (mNode.Parent.ChildCount = 1) then
  begin
    mFirst := mNode.Parent.StartPos.Line;
  end;
  Result := TTextEdit.Create(TTextRange.Create(mFirst, 0, AMember.LastLine + 1, 0), '');
end;

class function TClassEdits.DeleteMembers(ALayout: TClassLayout; const AIndexes: TArray<Integer>;
  ABodies: Boolean): TArray<TTextEdit>;
var
  mIndex: Integer;
  mMember: TClassMember;
  mRemaining: TArray<string>;
  mDone: TArray<TSyntaxNode>;
begin
  Result := nil;
  mDone := nil;
  for mIndex in AIndexes do
  begin
    mMember := ALayout.Members[mIndex];
    if NodeIn(mDone, mMember.Node) then
    begin
      Continue;
    end;
    mDone := mDone + [mMember.Node];
    mRemaining := nil;
    if mMember.IsFieldGroup then
    begin
      mRemaining := RemainingNames(ALayout, AIndexes, mMember);
    end;
    if mRemaining <> nil then
    begin
      // Übrige Namen der Gruppe behalten.
      Result := Result + [GroupEdit(ALayout, mMember, mRemaining)];
    end
    else
    begin
      Result := Result + [DeclarationDelete(mMember)];
      if ABodies and (mMember.Body <> nil) then
      begin
        Result := Result + [DeleteLines(ALayout, mMember.BodyFirstLine, mMember.BodyLastLine)];
      end;
    end;
  end;
end;

/// <summary>Zeilen von ADeclarations mit der Einrückung der Mitglieder und den Zeilenenden der Unit.</summary>
function IndentedBody(ALayout: TClassLayout; const ADeclarations: TArray<string>): string;
var
  mItem, mPart: string;
begin
  Result := '';
  for mItem in ADeclarations do
  begin
    for mPart in mItem.Split([#10]) do
    begin
      Result := Result + ALayout.MemberIndent + TrimRight(mPart) + ALayout.LineBreak;
    end;
  end;
end;

/// <summary>Letzter Abschnitt mit Sichtbarkeit AVisibility (ohne Schlüsselwort nur public); -1 ohne.</summary>
function SectionIndex(ALayout: TClassLayout; AVisibility: TClassVisibility): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ALayout.Sections) do
  begin
    if (ALayout.Sections[mIndex].Visibility = AVisibility) and
      ((ALayout.Sections[mIndex].HeadLine >= 0) or (AVisibility = TClassVisibility.Public_)) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Zeile eines neuen Abschnitts in der Reihenfolge der Sichtbarkeit: vor dem ersten mit höherer, sonst
/// vor end.</summary>
function NewSectionLine(ALayout: TClassLayout; AVisibility: TClassVisibility): Integer;
var
  mIndex: Integer;
begin
  Result := ALayout.EndLine;
  for mIndex := High(ALayout.Sections) downto 0 do
  begin
    if (ALayout.Sections[mIndex].HeadLine >= 0) and (ALayout.Sections[mIndex].Visibility > AVisibility) then
    begin
      Result := ALayout.Sections[mIndex].HeadLine;
    end;
  end;
end;

/// <summary>Erste Zeile der ersten Methode bzw. Property des Abschnitts; -1 ohne.</summary>
function FirstRoutineLine(ALayout: TClassLayout; const ASection: TClassSection): Integer;
var
  mIndex: Integer;
begin
  for mIndex in ASection.Members do
  begin
    if ALayout.Members[mIndex].IsMethod or (ALayout.Members[mIndex].Kind = TClassMemberKind.Property_) then
    begin
      Exit(ALayout.Members[mIndex].FirstLine);
    end;
  end;
  Result := -1;
end;

/// <summary>Zeile, vor der neue Mitglieder in ASection kommen: Felder (AFields) vor die erste Methode bzw.
/// Property, sonst hinter das letzte Mitglied bzw. die Kopfzeile des Abschnitts.</summary>
function SectionInsertLine(ALayout: TClassLayout; const ASection: TClassSection; AFields: Boolean): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if AFields then
  begin
    Result := FirstRoutineLine(ALayout, ASection);
  end;
  if Result >= 0 then
  begin
    Exit;
  end;
  Result := ASection.HeadLine;
  if Result < 0 then
  begin
    Result := ALayout.HeaderLine;
  end;
  for mIndex in ASection.Members do
  begin
    if ALayout.Members[mIndex].LastLine > Result then
    begin
      Result := ALayout.Members[mIndex].LastLine;
    end;
  end;
  Inc(Result);
end;

class function TClassEdits.InsertMembers(ALayout: TClassLayout; AVisibility: TClassVisibility; AFields: Boolean;
  const ADeclarations: TArray<string>): TTextEdit;
var
  mBody: string;
  mFound: Integer;
begin
  mBody := IndentedBody(ALayout, ADeclarations);
  mFound := SectionIndex(ALayout, AVisibility);
  if mFound < 0 then
  begin
    Result := InsertBeforeLine(NewSectionLine(ALayout, AVisibility), ALayout.Indent + VisibilityName(AVisibility) +
      ALayout.LineBreak + mBody);
  end
  else
  begin
    Result := InsertBeforeLine(SectionInsertLine(ALayout, ALayout.Sections[mFound], AFields), mBody);
  end;
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
