unit Atlas.Common.Editing.ExtractInterface;

// „Interface aus Klasse herauslösen“ (#664), Gegenstück zu „Interface
// implementieren“ (#466):
//   - Kandidaten: public- und published-Methoden und -Properties der Klasse.
//     Vorab gewählt sind alle public-Methoden. Konstruktoren, Destruktoren,
//     Klassenmethoden, Operatoren und generische Methoden kann ein Interface
//     nicht enthalten; sie stehen mit Grund in der Liste, sind aber nicht
//     wählbar. Ereignis-Properties (Typ eines Methodenzeigers) und Properties
//     sind wählbar, aber nicht vorab gewählt; Klassen-Properties und
//     Properties ohne Typ (nur Sichtbarkeit geändert) nicht wählbar.
//   - Name: Vorschlag I + Klassenname ohne T, gültiger Bezeichner, kein
//     anderer Name im Gültigkeitsbereich (Rückfrage über TNameInUse).
//   - Interface: neue GUID, die Methoden mit ihrer Signatur (Standardwerte,
//     overload, const/var/out und Aufrufkonventionen bleiben, virtual,
//     override, reintroduce, abstract, inline, message usw. entfallen), die
//     Properties mit Getter und Setter (stored, Standardwerte, nodefault und
//     implements entfallen) und die Doku-Kommentare. Zugriffsmethoden einer
//     gewählten Property kommen mit ins Interface. Liest oder schreibt eine
//     Property ein Feld, legt Atlas in der Klasse GetX/SetX (private) an und
//     stellt die Property darauf um.
//   - Klasse: Das Interface kommt in die Vorfahrenliste. Ohne Vorfahr oder mit
//     TObject wird TInterfacedObject der Vorfahr; hat die Klasse schon
//     Interfaces, implementiert sie IInterface schon. Sonst prüft
//     TInterfaceSupport die Vorfahrenkette; ohne IInterface-Implementierung
//     bzw. unbekannt gibt es einen Hinweis für die Vorschau.
//   - Ziel: dieselbe Unit (direkt vor der Klasse samt Doku und Attributen)
//     oder eine andere Unit. Dafür liefert der Plan den Text des Interfaces
//     und die Namen der Typen in den Signaturen; uses, neue Unit und Projekt
//     macht Atlas.Common.Lsp.ExtractInterface.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout;

type
  {$SCOPEDENUMS ON}
  TInterfaceSupport = (Yes, No, Unknown);
  TExtractCandidateKind = (Method, Property_);
  {$SCOPEDENUMS OFF}

  /// <summary>Vorfahren einer Klasse (erster Eintrag = Vorfahr); False, wenn die Klasse unbekannt ist.</summary>
  TClassAncestorsLookup = reference to function(const AClassName: string; out AAncestors: TArray<string>): Boolean;
  /// <summary>Ist AName im Gültigkeitsbereich der Klasse schon vergeben?</summary>
  TNameInUse = reference to function(const AName: string): Boolean;
  /// <summary>Ist ATypeName ein Methodenzeiger (procedure … of object, reference to)?</summary>
  TIsMethodPointer = reference to function(const ATypeName: string): Boolean;

  TExtractCandidate = record
    /// <summary>Index des Mitglieds in TClassLayout.Members.</summary>
    Id: Integer;
    Name: string;
    Kind: TExtractCandidateKind;
    /// <summary>Kopf ohne Direktiven bzw. Property-Deklaration.</summary>
    Display: string;
    Visibility: TClassVisibility;
    Checked: Boolean;
    Enabled: Boolean;
    /// <summary>Warum nicht wählbar; '' sonst.</summary>
    Reason: string;
  end;

  TExtractInterfaceInfo = record
    ClassName: string;
    SuggestedName: string;
    Candidates: TArray<TExtractCandidate>;
    /// <summary>Hinweise vorab (Vorfahr ohne IInterface).</summary>
    Notes: TArray<string>;
  end;

  TExtractInterfaceRequest = record
    Name: string;
    /// <summary>Ids der gewählten Kandidaten.</summary>
    Members: TArray<Integer>;
    /// <summary>GUID samt geschweiften Klammern.</summary>
    Guid: string;
    /// <summary>Das Interface steht in derselben Unit (sonst liefert der Plan nur seinen Text).</summary>
    SameUnit: Boolean;
  end;

  TExtractInterfacePlan = record
    ClassName: string;
    InterfaceName: string;
    /// <summary>Deklaration des Interfaces ohne Einrückung, Zeilen mit #10, ohne Umbruch am Ende.</summary>
    Declaration: string;
    /// <summary>Änderungen an der Unit der Klasse (mit SameUnit samt dem Interface).</summary>
    Edits: TArray<TTextEdit>;
    /// <summary>Erste Bezeichner der Typen in den Signaturen (für uses einer anderen Ziel-Unit).</summary>
    TypeNames: TArray<string>;
    /// <summary>Methoden im Interface (einschließlich mitgenommener Zugriffsmethoden).</summary>
    Methods: TArray<string>;
    Warnings: TArray<string>;
    /// <summary>Die Klasse steht im interface-Teil ihrer Unit; Offset ihrer Deklaration.</summary>
    InInterface: Boolean;
    ClassOffset: Integer;
  end;

  TExtractInterface = class
  public const
    Kind = 'refactor.extract';
  public
    /// <summary>I + Klassenname ohne führendes T (TKunde → IKunde).</summary>
    class function DefaultName(const AClassName: string): string; static;
    /// <summary>Klasse auf der Kopfzeile ALine; nil ohne.</summary>
    class function ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode; static;
    /// <summary>Implementiert eine Klasse mit Vorfahr AAncestor IInterface? Bekannte RTL-Klassen, Klassen mit
    /// Interfaces in der Vorfahrenliste und deren Nachfahren ja; die Kette bis TObject ohne solche nein.</summary>
    class function Supports(const AAncestor: string; const ALookup: TClassAncestorsLookup): TInterfaceSupport;
      static;
    /// <summary>Kandidaten und Vorschlag für die Klasse auf Zeile ALine; False mit Grund ohne Klasse oder ohne
    /// Kandidaten.</summary>
    class function Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const ALookup: TClassAncestorsLookup; const AIsMethodPointer: TIsMethodPointer;
      out AInfo: TExtractInterfaceInfo; out AReason: string): Boolean; static;
    /// <summary>Änderungen für ARequest; False mit Grund (Name ungültig oder vergeben, nichts gewählt,
    /// Kandidat nicht wählbar).</summary>
    class function Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
      const ARequest: TExtractInterfaceRequest; const ALookup: TClassAncestorsLookup;
      const ANameInUse: TNameInUse; const AIsMethodPointer: TIsMethodPointer; out APlan: TExtractInterfacePlan;
      out AReason: string): Boolean; static;
    /// <summary>Änderung, die ADeclaration (aus dem Plan) samt "type" vor die implementation einer anderen Unit
    /// setzt; False ohne interface-Teil.</summary>
    class function InsertIntoUnit(ATree: TSyntaxTree; const AText, ADeclaration: string;
      out AEdit: TTextEdit): Boolean; static;
    /// <summary>Text einer neuen Unit mit dem Interface; AUses darf leer sein.</summary>
    class function NewUnitText(const AUnitName, ADeclaration: string; const AUses: TArray<string>;
      const ALineBreak: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.TextChanges;

const
  /// <summary>Klassen der RTL, die IInterface implementieren.</summary>
  InterfacedRoots: array[0..6] of string = ('TInterfacedObject', 'TAggregatedObject', 'TContainedObject',
    'TComponent', 'TInterfacedPersistent', 'TInterfaceList', 'TAutoIntfObject');
  /// <summary>Direktiven, die ins Interface mitkommen.</summary>
  KeptDirectives: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');

function StripT(const AName: string): string;
begin
  Result := AName;
  if (Length(Result) > 1) and CharInSet(Result[1], ['T', 't']) and CharInSet(Result[2], ['A'..'Z']) then
    Result := Copy(Result, 2, MaxInt);
end;

{ TExtractInterface }

class function TExtractInterface.DefaultName(const AClassName: string): string;
begin
  Result := 'I' + StripT(AClassName);
end;

class function TExtractInterface.ClassAt(ATree: TSyntaxTree; ALine: Integer): TSyntaxNode;
begin
  Result := TClassLayout.DeclAt(ATree, ALine, False);
end;

class function TExtractInterface.Supports(const AAncestor: string;
  const ALookup: TClassAncestorsLookup): TInterfaceSupport;
var
  Name: string;
  Chain: TArray<string>;
  Depth: Integer;
begin
  Name := AAncestor;
  if Pos('<', Name) > 0 then
    Name := Copy(Name, 1, Pos('<', Name) - 1);
  if Pos('.', Name) > 0 then
    Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  for Depth := 1 to 32 do
  begin
    if MatchText(Name, InterfacedRoots) then
      Exit(TInterfaceSupport.Yes);
    if SameText(Name, 'TObject') then
      Exit(TInterfaceSupport.No);
    if not Assigned(ALookup) or not ALookup(Name, Chain) then
      Exit(TInterfaceSupport.Unknown);
    // Interfaces in der Liste: die Klasse implementiert IInterface selbst.
    if Length(Chain) > 1 then
      Exit(TInterfaceSupport.Yes);
    if Chain = nil then
      Exit(TInterfaceSupport.No);
    Name := Chain[0];
    if Pos('<', Name) > 0 then
      Name := Copy(Name, 1, Pos('<', Name) - 1);
    if Pos('.', Name) > 0 then
      Name := Copy(Name, LastDelimiter('.', Name) + 1, MaxInt);
  end;
  Result := TInterfaceSupport.Unknown;
end;

function Candidates(ALayout: TClassLayout; const AIsMethodPointer: TIsMethodPointer): TArray<TExtractCandidate>;
var
  Index: Integer;
  Member: TClassMember;
  Item: TExtractCandidate;
begin
  Result := nil;
  for Index := 0 to High(ALayout.Members) do
  begin
    Member := ALayout.Members[Index];
    if not (Member.Visibility in [TClassVisibility.Public_, TClassVisibility.Published_]) then
      Continue;
    if not (Member.IsMethod or (Member.Kind = TClassMemberKind.Property_) or
      (Member.Kind = TClassMemberKind.Other) and (Member.Node.Kind = TSyntaxKind.RoutineHeader)) then
      Continue;
    Item := Default(TExtractCandidate);
    Item.Id := Index;
    Item.Name := Member.Name;
    Item.Visibility := Member.Visibility;
    Item.Enabled := True;
    if Member.Kind = TClassMemberKind.Property_ then
    begin
      Item.Kind := TExtractCandidateKind.Property_;
      Item.Display := ALayout.Declaration(Index);
      if Member.IsClassMember then
        Item.Reason := 'Klassen-Property'
      else if Member.IsRedeclaration then
        Item.Reason := 'Property ohne Typ (geerbt)'
      else if (Member.ReadAccessor = '') and (Member.WriteAccessor = '') then
        Item.Reason := 'Property ohne read und write';
    end
    else
    begin
      Item.Kind := TExtractCandidateKind.Method;
      Item.Display := ALayout.Head(Index);
      if Member.Kind = TClassMemberKind.Constructor_ then
        Item.Reason := 'Konstruktor'
      else if Member.Kind = TClassMemberKind.Destructor_ then
        Item.Reason := 'Destruktor'
      else if Member.Kind = TClassMemberKind.Other then
        Item.Reason := 'Operator'
      else if Member.IsClassMember then
        Item.Reason := 'Klassenmethode'
      else if Member.IsGeneric then
        Item.Reason := 'generische Methode (in Interfaces nicht erlaubt)'
      else if Member.HasDirective('message') then
        Item.Reason := 'Botschaftsbehandlung';
    end;
    Item.Enabled := Item.Reason = '';
    Item.Checked := Item.Enabled and (Item.Kind = TExtractCandidateKind.Method) and
      (Member.Visibility = TClassVisibility.Public_);
    // Ereignis-Properties sind wählbar, aber nicht vorab gewählt (wie alle Properties).
    if Item.Enabled and (Item.Kind = TExtractCandidateKind.Property_) and Assigned(AIsMethodPointer) and
      AIsMethodPointer(Member.TypeName) then
      Item.Display := Item.Display + '  // Ereignis';
    Result := Result + [Item];
  end;
end;

function AncestorNote(ALayout: TClassLayout; const ALookup: TClassAncestorsLookup; out ANewAncestors: TArray<string>;
  const AInterfaceName: string): string;
var
  First: string;
begin
  Result := '';
  ANewAncestors := Copy(ALayout.Ancestors);
  if (Length(ANewAncestors) = 0) or SameText(ANewAncestors[0], 'TObject') or
    SameText(ANewAncestors[0], 'System.TObject') then
  begin
    if Length(ANewAncestors) > 1 then
      // TObject mit Interfaces: Die Klasse implementiert IInterface schon selbst.
      ANewAncestors := ANewAncestors + [AInterfaceName]
    else
      ANewAncestors := ['TInterfacedObject', AInterfaceName];
    Exit;
  end;
  if Length(ANewAncestors) = 1 then
  begin
    First := ANewAncestors[0];
    case TExtractInterface.Supports(First, ALookup) of
      TInterfaceSupport.No:
        Result := Format('%s implementiert IInterface nicht: %s fehlen _AddRef, _Release und QueryInterface ' +
          '(Referenzzählen).', [First, ALayout.Name]);
      TInterfaceSupport.Unknown:
        Result := Format('Ob %s IInterface implementiert, ist nicht bekannt; sonst fehlen %s _AddRef, _Release und ' +
          'QueryInterface (Referenzzählen).', [First, ALayout.Name]);
    end;
  end;
  ANewAncestors := ANewAncestors + [AInterfaceName];
end;

class function TExtractInterface.Prepare(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ALookup: TClassAncestorsLookup; const AIsMethodPointer: TIsMethodPointer; out AInfo: TExtractInterfaceInfo;
  out AReason: string): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Item: TExtractCandidate;
  Ancestors: TArray<string>;
  Note: string;
begin
  AInfo := Default(TExtractInterfaceInfo);
  AReason := '';
  Decl := ClassAt(ATree, ALine);
  if Decl = nil then
  begin
    AReason := 'An dieser Stelle steht keine Klasse.';
    Exit(False);
  end;
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    AInfo.ClassName := Layout.Name;
    AInfo.SuggestedName := DefaultName(Layout.Name);
    AInfo.Candidates := Candidates(Layout, AIsMethodPointer);
    Note := AncestorNote(Layout, ALookup, Ancestors, AInfo.SuggestedName);
    if Note <> '' then
      AInfo.Notes := AInfo.Notes + [Note];
  finally
    Layout.Free;
  end;
  for Item in AInfo.Candidates do
    if Item.Enabled then
      Exit(True);
  AReason := Format('%s hat keine public- oder published-Methoden und -Properties für ein Interface.',
    [AInfo.ClassName]);
  Result := False;
end;

/// <summary>Erste Bezeichner aller Typverweise unter ANode.</summary>
procedure CollectTypeNames(ANode: TSyntaxNode; var ANames: TArray<string>);
var
  Found: TArray<string>;
  Name: string;
begin
  // Var-Parameter lassen sich nicht einfangen: erst sammeln, dann anhängen.
  Found := nil;
  ANode.Walk(
    function(AChild: TSyntaxNode): Boolean
    var
      Part: string;
    begin
      Result := True;
      if AChild.Kind <> TSyntaxKind.TypeReference then
        Exit;
      Part := AChild.Name;
      if Pos('.', Part) > 0 then
        Part := Copy(Part, 1, Pos('.', Part) - 1);
      if (Part <> '') and IsIdentifier(Part) then
        Found := Found + [Part];
    end);
  for Name in Found do
    if IndexText(Name, ANames) < 0 then
      ANames := ANames + [Name];
end;

function MethodDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in ALayout.Members[AIndex].Directives do
    if MatchText(Directive, KeptDirectives) then
      Result := Result + ' ' + Directive + ';';
end;

function PropertyDeclaration(const AMember: TClassMember; const AReader, AWriter: string): string;
begin
  Result := 'property ' + AMember.Name;
  if AMember.Parameters <> '' then
    Result := Result + '[' + AMember.Parameters + ']';
  Result := Result + ': ' + AMember.TypeName;
  if AMember.IndexSpecifier <> '' then
    Result := Result + ' index ' + AMember.IndexSpecifier;
  if AReader <> '' then
    Result := Result + ' read ' + AReader;
  if AWriter <> '' then
    Result := Result + ' write ' + AWriter;
  Result := Result + ';';
  if AMember.IsDefaultArray then
    Result := Result + ' default;';
end;

/// <summary>Ist AName eine Methode der Klasse (Zugriffsmethode statt Feld)?</summary>
function MethodIndex(ALayout: TClassLayout; const AName: string): Integer;
var
  Index: Integer;
begin
  for Index in ALayout.Find(AName) do
    if ALayout.Members[Index].IsMethod then
      Exit(Index);
  Result := -1;
end;

function UniqueMemberName(ALayout: TClassLayout; const ABase: string; const ATaken: TArray<string>): string;
var
  Counter: Integer;
begin
  Result := ABase;
  Counter := 1;
  while (ALayout.Find(Result) <> nil) or (IndexText(Result, ATaken) >= 0) do
  begin
    Inc(Counter);
    Result := ABase + IntToStr(Counter);
  end;
end;

class function TExtractInterface.Plan(ATree: TSyntaxTree; const AText: string; ALine: Integer;
  const ARequest: TExtractInterfaceRequest; const ALookup: TClassAncestorsLookup; const ANameInUse: TNameInUse;
  const AIsMethodPointer: TIsMethodPointer; out APlan: TExtractInterfacePlan; out AReason: string): Boolean;
var
  Decl: TSyntaxNode;
  Layout: TClassLayout;
  Items: TArray<TExtractCandidate>;
  Item: TExtractCandidate;
  Chosen, Methods: TArray<Integer>;
  Id, Index, Accessor: Integer;
  Member: TClassMember;
  Found: Boolean;
  Lines, NewMethods, NewBodies, Taken: TArray<string>;
  Reader, Writer, Doc, Note, Text, Indent, Declaration, LineBreak, Getter, Setter, Value: string;
  Ancestors: TArray<string>;
  Edit: TTextEdit;
  PropertyEdits: TArray<TTextEdit>;
  BodiesLine: Integer;

  function Fail(const AMessage: string): Boolean;
  begin
    AReason := AMessage;
    Result := False;
  end;

  procedure AddMethod(AIndex: Integer);
  var
    Known: Integer;
  begin
    for Known in Methods do
      if Known = AIndex then
        Exit;
    Methods := Methods + [AIndex];
  end;

begin
  APlan := Default(TExtractInterfacePlan);
  AReason := '';
  Decl := ClassAt(ATree, ALine);
  if Decl = nil then
    Exit(Fail('An dieser Stelle steht keine Klasse.'));
  if not IsIdentifier(ARequest.Name) then
    Exit(Fail(Format('"%s" ist kein gültiger Bezeichner.', [ARequest.Name])));
  if ARequest.Members = nil then
    Exit(Fail('Es ist kein Mitglied gewählt.'));
  Layout := TClassLayout.Read(ATree, AText, Decl);
  try
    LineBreak := Layout.LineBreak;
    if SameText(ARequest.Name, Layout.Name) or (TClassLayout.DeclNamed(ATree, ARequest.Name) <> nil) or
      Assigned(ANameInUse) and ANameInUse(ARequest.Name) then
      Exit(Fail(Format('Der Name %s ist schon vergeben.', [ARequest.Name])));
    Items := Candidates(Layout, AIsMethodPointer);
    Chosen := nil;
    for Id in ARequest.Members do
    begin
      Found := False;
      for Item in Items do
        if Item.Id = Id then
        begin
          if not Item.Enabled then
            Exit(Fail(Format('%s kann nicht ins Interface: %s.', [Item.Name, Item.Reason])));
          Found := True;
        end;
      if not Found then
        Exit(Fail('Die Klasse hat sich geändert; bitte die Aktion erneut aufrufen.'));
      Chosen := Chosen + [Id];
    end;
    APlan.ClassName := Layout.Name;
    APlan.InterfaceName := ARequest.Name;
    APlan.InInterface := Layout.InInterface;
    APlan.ClassOffset := Decl.StartOffset;
    // Methoden in Reihenfolge der Klasse, dann die Zugriffsmethoden der Properties.
    Methods := nil;
    for Id in Chosen do
      if Layout.Members[Id].Kind <> TClassMemberKind.Property_ then
        AddMethod(Id);
    Lines := nil;
    NewMethods := nil;
    NewBodies := nil;
    Taken := nil;
    PropertyEdits := nil;
    for Id in Chosen do
    begin
      Member := Layout.Members[Id];
      if Member.Kind <> TClassMemberKind.Property_ then
        Continue;
      Reader := Member.ReadAccessor;
      Writer := Member.WriteAccessor;
      Getter := '';
      Setter := '';
      if Reader <> '' then
      begin
        Accessor := MethodIndex(Layout, Reader);
        if Accessor >= 0 then
        begin
          AddMethod(Accessor);
          if Layout.Members[Accessor].Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_,
            TClassVisibility.StrictProtected, TClassVisibility.Protected_] then
            APlan.Warnings := APlan.Warnings + [Format('%s kommt als Zugriffsmethode von %s mit ins Interface.',
              [Reader, Member.Name])];
        end
        else
        begin
          // Feld: Getter anlegen.
          Getter := UniqueMemberName(Layout, 'Get' + Member.Name, Taken);
          Taken := Taken + [Getter];
          NewMethods := NewMethods + [Format('function %s: %s;', [Getter, Member.TypeName])];
          NewBodies := NewBodies + [Format('function %s.%s: %s;', [Layout.Name, Getter, Member.TypeName]) +
            LineBreak + 'begin' + LineBreak + '  Result := ' + Reader + ';' + LineBreak + 'end;'];
          Reader := Getter;
        end;
      end;
      if Writer <> '' then
      begin
        Accessor := MethodIndex(Layout, Writer);
        if Accessor >= 0 then
        begin
          AddMethod(Accessor);
          if Layout.Members[Accessor].Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_,
            TClassVisibility.StrictProtected, TClassVisibility.Protected_] then
            APlan.Warnings := APlan.Warnings + [Format('%s kommt als Zugriffsmethode von %s mit ins Interface.',
              [Writer, Member.Name])];
        end
        else
        begin
          Setter := UniqueMemberName(Layout, 'Set' + Member.Name, Taken);
          Taken := Taken + [Setter];
          Value := 'Value';
          NewMethods := NewMethods + [Format('procedure %s(const %s: %s);', [Setter, Value, Member.TypeName])];
          NewBodies := NewBodies + [Format('procedure %s.%s(const %s: %s);', [Layout.Name, Setter, Value,
            Member.TypeName]) + LineBreak + 'begin' + LineBreak + '  ' + Writer + ' := ' + Value + ';' + LineBreak +
            'end;'];
          Writer := Setter;
        end;
      end;
      // Property in der Klasse auf die neuen Methoden umstellen.
      if (Getter <> '') and TClassEdits.ReplaceAccessor(Layout, Id, 'read', Getter, Edit) then
        PropertyEdits := PropertyEdits + [Edit];
      if (Setter <> '') and TClassEdits.ReplaceAccessor(Layout, Id, 'write', Setter, Edit) then
        PropertyEdits := PropertyEdits + [Edit];
      for Doc in Layout.DocLines(Id) do
        Lines := Lines + ['  ' + Doc];
      Lines := Lines + ['  ' + PropertyDeclaration(Member, Reader, Writer)];
    end;
    // Methoden vor die Properties.
    Declaration := '';
    for Index in Methods do
    begin
      for Doc in Layout.DocLines(Index) do
        Declaration := Declaration + #10'  ' + Doc;
      Declaration := Declaration + #10'  ' + MethodDeclaration(Layout, Index);
      APlan.Methods := APlan.Methods + [Layout.Members[Index].Name];
      CollectTypeNames(Layout.Members[Index].Node, APlan.TypeNames);
    end;
    for Index := 0 to High(NewMethods) do
      Declaration := Declaration + #10'  ' + NewMethods[Index];
    for Text in Lines do
      Declaration := Declaration + #10 + Text;
    for Id in Chosen do
      if Layout.Members[Id].Kind = TClassMemberKind.Property_ then
        CollectTypeNames(Layout.Members[Id].Node, APlan.TypeNames);
    APlan.Declaration := ARequest.Name + ' = interface' + #10'  [''' + ARequest.Guid + ''']' + Declaration +
      #10'end;';
    // Klasse: Vorfahrenliste, neue Zugriffsmethoden mit Rümpfen, umgestellte Properties.
    Note := AncestorNote(Layout, ALookup, Ancestors, ARequest.Name);
    if Note <> '' then
      APlan.Warnings := [Note] + APlan.Warnings;
    APlan.Edits := [TClassEdits.SetAncestors(Layout, Ancestors)] + PropertyEdits;
    if NewMethods <> nil then
    begin
      APlan.Edits := APlan.Edits + [TClassEdits.InsertMembers(Layout, TClassVisibility.Private_, False, NewMethods)];
      BodiesLine := TClassEdits.BodiesEnd(ATree, AText, Layout.Name);
      if BodiesLine < 0 then
        Exit(Fail('Die Unit hat keinen implementation-Teil für die neuen Zugriffsmethoden.'));
      APlan.Edits := APlan.Edits + [TClassEdits.InsertBodies(AText, BodiesLine, NewBodies)];
    end;
    if ARequest.SameUnit then
    begin
      Indent := Layout.Indent;
      Text := '';
      for Doc in APlan.Declaration.Split([#10]) do
        Text := Text + Indent + Doc + LineBreak;
      APlan.Edits := APlan.Edits + [TClassEdits.InsertBeforeLine(AText, Layout.FirstLine, Text + LineBreak)];
    end;
  finally
    Layout.Free;
  end;
  Result := True;
end;

class function TExtractInterface.InsertIntoUnit(ATree: TSyntaxTree; const AText, ADeclaration: string;
  out AEdit: TTextEdit): Boolean;
var
  Implementation_, Interface_: TSyntaxNode;
  Index, Line: Integer;
  LineBreak, Text, Part: string;
begin
  Implementation_ := nil;
  Interface_ := nil;
  for Index := 0 to ATree.Root.ChildCount - 1 do
    if ATree.Root[Index].Kind = TSyntaxKind.ImplementationSection then
      Implementation_ := ATree.Root[Index]
    else if ATree.Root[Index].Kind = TSyntaxKind.InterfaceSection then
      Interface_ := ATree.Root[Index];
  if (Interface_ = nil) or (Implementation_ = nil) then
    Exit(False);
  LineBreak := TTextLines.LineBreakOf(AText);
  Text := 'type' + LineBreak;
  for Part in ADeclaration.Split([#10]) do
    Text := Text + '  ' + Part + LineBreak;
  Line := Implementation_.StartPos.Line;
  AEdit := TClassEdits.InsertBeforeLine(AText, Line, Text + LineBreak);
  Result := True;
end;

class function TExtractInterface.NewUnitText(const AUnitName, ADeclaration: string; const AUses: TArray<string>;
  const ALineBreak: string): string;
var
  Part: string;
begin
  Result := 'unit ' + AUnitName + ';' + ALineBreak + ALineBreak + 'interface' + ALineBreak + ALineBreak;
  if AUses <> nil then
    Result := Result + 'uses' + ALineBreak + '  ' + string.Join(',' + ALineBreak + '  ', AUses) + ';' + ALineBreak +
      ALineBreak;
  Result := Result + 'type' + ALineBreak;
  for Part in ADeclaration.Split([#10]) do
    Result := Result + '  ' + Part + ALineBreak;
  Result := Result + ALineBreak + 'implementation' + ALineBreak + ALineBreak + 'end.' + ALineBreak;
end;

end.
