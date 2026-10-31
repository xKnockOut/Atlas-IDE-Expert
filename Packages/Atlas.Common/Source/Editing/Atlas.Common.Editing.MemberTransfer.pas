unit Atlas.Common.Editing.MemberTransfer;

// Gemeinsame Schritte der Umbauten, die Mitglieder zwischen Klassen einer
// Vererbungslinie bewegen: „Basisklasse herauslösen“ (#713) und „Mitglied in
// Vorfahr oder Nachfahr verschieben“ (#675).
//
//   - Kandidaten: Felder, Klassenvariablen, Methoden und Properties einer
//     Klasse samt Abhängigkeiten (welche Mitglieder ein Mitglied benutzt) und
//     der Frage, ob eine Methode oben abstrakt deklariert werden kann.
//   - Prüfung: Was ganz wandert, darf nur Mitglieder benutzen, die mitwandern.
//   - Deklarationen für das Ziel: unverändert (samt Doku und Attributen),
//     abstrakt (virtual; abstract;), virtuell oder überschreibend.
//   - Änderungen an der Quelle: aus virtual/dynamic wird override,
//     reintroduce und abstract fallen weg; Abschnitte ohne Mitglieder
//     fallen weg.
//   - Sichtbarkeit: Ob ein privates Mitglied gehoben werden muss, weil es
//     am alten Ort weiter benutzt wird; Umsetzen von Mitgliedern in einen
//     Abschnitt anderer Sichtbarkeit.
//   - Einfügen in eine vorhandene Klasse: Deklarationen je Sichtbarkeit
//     (Felder vor Methoden) und Rümpfe hinter die Rümpfe der Klasse.
//
// Alles arbeitet auf Text: Änderungen anwenden, neu parsen, weiter.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.ClassLayout;

type
  {$SCOPEDENUMS ON}
  TTransferKind = (Field, Method, Property_);
  {$SCOPEDENUMS OFF}

  TTransferCandidate = record
    /// <summary>Index des Mitglieds in TClassLayout.Members.</summary>
    Id: Integer;
    Name: string;
    Kind: TTransferKind;
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

  /// <summary>Benutzt das bleibende Mitglied AUser das gehobene Mitglied noch (z. B. nach dem Aufteilen eines
  /// Konstruktors)?</summary>
  TStillUses = reference to function(AUser: Integer): Boolean;

  /// <summary>Ein Eintrag für eine vorhandene Klasse: Deklaration ohne Einrückung (Zeilen mit #10), Sichtbarkeit,
  /// Feld oder nicht.</summary>
  TTransferDeclaration = record
    Text: string;
    Visibility: TClassVisibility;
    IsField: Boolean;
    class function Create(const AText: string; AVisibility: TClassVisibility; AIsField: Boolean):
      TTransferDeclaration; static;
  end;

  TMemberTransfer = class
  public
    class function Has(const AList: TArray<Integer>; AValue: Integer): Boolean; static;
    class function HasAll(const AItems, AList: TArray<Integer>): Boolean; static;
    /// <summary>Feld, Klassenvariable, Methode oder Property; False bei anderem.</summary>
    class function KindOf(const AMember: TClassMember; out AKind: TTransferKind): Boolean; static;
    /// <summary>Warum eine Methode oben nicht abstrakt werden kann; '' wenn doch.</summary>
    class function AbstractBlocker(const AMember: TClassMember): string; static;
    /// <summary>Kandidaten der Klasse in Reihenfolge der Deklaration; Abhängigkeiten nur auf andere Kandidaten.
    /// </summary>
    class function Candidates(ALayout: TClassLayout): TArray<TTransferCandidate>; static;
    /// <summary>Index von AId in ACandidates; -1 ohne.</summary>
    class function IndexOf(const ACandidates: TArray<TTransferCandidate>; AId: Integer): Integer; static;
    /// <summary>„A braucht B“ für jedes Mitglied aus AMoved, das ein Mitglied außerhalb von AChosen benutzt.
    /// </summary>
    class function MissingNeeds(ALayout: TClassLayout; const AMoved, AChosen: TArray<Integer>): TArray<string>;
      static;
    /// <summary>Muss das private Mitglied AId gehoben werden, weil es am alten Ort weiter benutzt wird? Ein
    /// strict-private-Mitglied immer dann, ein private-Mitglied nur mit ASameUnit = False oder wenn Code
    /// außerhalb der Klasse es benutzt. AMoved: Mitglieder, die mitgehen; AStaysUsed entscheidet für
    /// Konstruktoren und Destruktoren (nil: sie zählen wie alle).</summary>
    class function MustRaise(ALayout: TClassLayout; AId: Integer; const AMoved: TArray<Integer>;
      AAlwaysUsed, ASameUnit: Boolean; const AStaysUsed: TStillUses): Boolean; static;
    /// <summary>Änderungen, die aus dem Kopf AHeader eine überschreibende Methode machen: virtual/dynamic →
    /// override, reintroduce und abstract weg; ohne virtual mit AAddOverride override vor den Hinweisdirektiven
    /// bzw. am Ende.</summary>
    class function OverrideEdits(ALayout: TClassLayout; AHeader: TSyntaxNode; AAddOverride: Boolean):
      TArray<TTextEdit>; static;
    /// <summary>Direktiven des Kopfs AHeader als Text in Reihenfolge.</summary>
    class function DirectiveTexts(ALayout: TClassLayout; AHeader: TSyntaxNode): TArray<string>; static;
    /// <summary>Abstrakte Deklaration für oben: Kopf, reintroduce, behaltene Direktiven, virtual; abstract;.
    /// </summary>
    class function AbstractDeclaration(ALayout: TClassLayout; AIndex: Integer): string; static;
    /// <summary>Deklaration mit virtual: Kopf, behaltene Direktiven, virtual;, Hinweisdirektiven.</summary>
    class function VirtualDeclaration(ALayout: TClassLayout; AIndex: Integer): string; static;
    /// <summary>Überschreibende Deklaration: Kopf, behaltene Direktiven, override;, Hinweisdirektiven.</summary>
    class function OverrideDeclaration(ALayout: TClassLayout; AIndex: Integer): string; static;
    /// <summary>Deklarationszeilen eines Mitglieds (samt Doku und Attributen, Einrückung wie in der Klasse); eine
    /// Feldgruppe nur mit dem einen Namen; eine Klassenvariable mit class var davor.</summary>
    class function MemberLines(ALayout: TClassLayout; AIndex: Integer): TArray<string>; static;
    /// <summary>MemberLines ohne die Einrückung der Mitglieder, mit #10 verbunden (für InsertInto).</summary>
    class function MemberText(ALayout: TClassLayout; AIndex: Integer): string; static;
    /// <summary>Doku-Zeilen von AIndex und ADeclaration, mit #10 verbunden.</summary>
    class function WithDoc(ALayout: TClassLayout; AIndex: Integer; const ADeclaration: string): string; static;
    /// <summary>Benutzt Code außerhalb der Klasse und ihrer Rümpfe AName als ".AName"?</summary>
    class function UsedOutside(ALayout: TClassLayout; const AName: string): Boolean; static;
    /// <summary>Mitglied in ALayout, das AOld (aus einem früheren Stand) entspricht: Name, Art und Parametertypen;
    /// -1 ohne.</summary>
    class function Same(ALayout: TClassLayout; const AOld: TClassMember): Integer; static;
    /// <summary>Parst AText und liest die Klasse AName; nil (und ATree nil) ohne sie. Der Aufrufer gibt beides
    /// frei.</summary>
    class function ParseLayout(const AText, AName: string; out ATree: TSyntaxTree): TClassLayout; static;
    /// <summary>Löschungen der Abschnittsköpfe, deren Mitglieder alle in ARemoved stehen.</summary>
    class function EmptiedSections(ALayout: TClassLayout; const ARemoved: TArray<Integer>): TArray<TTextEdit>;
      static;
    /// <summary>Setzt die Mitglieder AMembers (aus einem früheren Stand) der Klasse AClassName in AText in den
    /// Abschnitt AVisibility um; leere Abschnitte fallen weg. False ohne die Klasse.</summary>
    class function Relocate(var AText: string; const AClassName: string; const AMembers: TArray<TClassMember>;
      AVisibility: TClassVisibility): Boolean; static;
    /// <summary>Fügt ADeclarations in die Klasse AClassName in AText ein, je Sichtbarkeit Felder vor Methoden;
    /// ABodies hinter die Rümpfe der Klasse. False mit Grund ohne Klasse oder ohne implementation-Teil.</summary>
    class function InsertInto(var AText: string; const AClassName: string;
      const ADeclarations: TArray<TTransferDeclaration>; const ABodies: TArray<string>;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.TreeCache,
  System.StrUtils,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.TextChanges;

const
  /// <summary>Direktiven, die eine neu geschriebene Deklaration behält.</summary>
  KeptDirectives: array[0..5] of string = ('overload', 'stdcall', 'safecall', 'cdecl', 'register', 'pascal');
  HintDirectives: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');

function LinesRange(AFirstLine, ALastLine: Integer): TTextRange;
begin
  Result := TTextRange.Create(AFirstLine, 0, ALastLine + 1, 0);
end;

{ TTransferDeclaration }

class function TTransferDeclaration.Create(const AText: string; AVisibility: TClassVisibility;
  AIsField: Boolean): TTransferDeclaration;
begin
  Result.Text := AText;
  Result.Visibility := AVisibility;
  Result.IsField := AIsField;
end;

{ TMemberTransfer }

class function TMemberTransfer.Has(const AList: TArray<Integer>; AValue: Integer): Boolean;
var
  Item: Integer;
begin
  for Item in AList do
    if Item = AValue then
      Exit(True);
  Result := False;
end;

class function TMemberTransfer.HasAll(const AItems, AList: TArray<Integer>): Boolean;
var
  Item: Integer;
begin
  for Item in AItems do
    if not Has(AList, Item) then
      Exit(False);
  Result := True;
end;

class function TMemberTransfer.KindOf(const AMember: TClassMember; out AKind: TTransferKind): Boolean;
begin
  Result := True;
  AKind := TTransferKind.Field;
  case AMember.Kind of
    TClassMemberKind.Field, TClassMemberKind.ClassVar:
      AKind := TTransferKind.Field;
    TClassMemberKind.Method:
      AKind := TTransferKind.Method;
    TClassMemberKind.Property_:
      AKind := TTransferKind.Property_;
  else
    Result := False;
  end;
end;

class function TMemberTransfer.AbstractBlocker(const AMember: TClassMember): string;
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

class function TMemberTransfer.Candidates(ALayout: TClassLayout): TArray<TTransferCandidate>;
var
  Index, Need: Integer;
  Member: TClassMember;
  Item: TTransferCandidate;
  Kind, NeedKind: TTransferKind;
begin
  Result := nil;
  for Index := 0 to High(ALayout.Members) do
  begin
    Member := ALayout.Members[Index];
    if not KindOf(Member, Kind) then
      Continue;
    Item := Default(TTransferCandidate);
    Item.Id := Index;
    Item.Name := Member.Name;
    Item.Kind := Kind;
    Item.Visibility := Member.Visibility;
    Item.Enabled := True;
    if Kind = TTransferKind.Method then
      Item.Display := ALayout.Head(Index)
    else
      Item.Display := ALayout.Declaration(Index);
    if Member.IsRedeclaration then
    begin
      Item.Enabled := False;
      Item.Reason := 'ändert nur die Sichtbarkeit eines geerbten Mitglieds';
    end
    else if Kind = TTransferKind.Method then
    begin
      Item.Reason := AbstractBlocker(Member);
      Item.CanAbstract := Item.Reason = '';
    end;
    for Need in ALayout.UsedBy(Index) do
      if KindOf(ALayout.Members[Need], NeedKind) then
        Item.Needs := Item.Needs + [Need];
    Result := Result + [Item];
  end;
end;

class function TMemberTransfer.IndexOf(const ACandidates: TArray<TTransferCandidate>; AId: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(ACandidates) do
    if ACandidates[Index].Id = AId then
      Exit(Index);
  Result := -1;
end;

class function TMemberTransfer.MissingNeeds(ALayout: TClassLayout; const AMoved,
  AChosen: TArray<Integer>): TArray<string>;
var
  Id, Need: Integer;
  Kind: TTransferKind;
  Text: string;
begin
  Result := nil;
  for Id in AMoved do
    for Need in ALayout.UsedBy(Id) do
      if not Has(AChosen, Need) and KindOf(ALayout.Members[Need], Kind) then
      begin
        Text := Format('%s braucht %s', [ALayout.Members[Id].Name, ALayout.Members[Need].Name]);
        if IndexText(Text, Result) < 0 then
          Result := Result + [Text];
      end;
end;

class function TMemberTransfer.MustRaise(ALayout: TClassLayout; AId: Integer; const AMoved: TArray<Integer>;
  AAlwaysUsed, ASameUnit: Boolean; const AStaysUsed: TStillUses): Boolean;
var
  Member: TClassMember;
  User: Integer;
begin
  Member := ALayout.Members[AId];
  if not (Member.Visibility in [TClassVisibility.StrictPrivate, TClassVisibility.Private_]) then
    Exit(False);
  // In derselben Unit sieht die Klasse private Mitglieder ihrer Vorfahren und Nachfahren ohnehin.
  if (Member.Visibility = TClassVisibility.Private_) and ASameUnit then
    Exit(False);
  Result := AAlwaysUsed;
  if not Result then
    for User in ALayout.UsersOf(AId) do
    begin
      if Has(AMoved, User) then
        Continue;
      if Assigned(AStaysUsed) and (ALayout.Members[User].Kind in [TClassMemberKind.Constructor_,
        TClassMemberKind.Destructor_]) then
        Result := AStaysUsed(User)
      else
        Result := True;
      if Result then
        Break;
    end;
  if not Result and (Member.Visibility = TClassVisibility.Private_) then
    Result := UsedOutside(ALayout, Member.Name);
end;

class function TMemberTransfer.DirectiveTexts(ALayout: TClassLayout; AHeader: TSyntaxNode): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to AHeader.ChildCount - 1 do
    if AHeader[Index].Kind = TSyntaxKind.Directive then
      Result := Result + [CollapseSpace(ALayout.TextOf(AHeader[Index]))];
end;

class function TMemberTransfer.OverrideEdits(ALayout: TClassLayout; AHeader: TSyntaxNode;
  AAddOverride: Boolean): TArray<TTextEdit>;
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
    else if SameText(Directive.Name, 'override') then
      Found := True
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

/// <summary>Kopf, behaltene Direktiven, AMiddle (z. B. "virtual;"), Hinweisdirektiven.</summary>
function Rewritten(ALayout: TClassLayout; AIndex: Integer; const AMiddle: string): string;
var
  Directive: string;
begin
  Result := ALayout.Head(AIndex);
  for Directive in ALayout.Members[AIndex].Directives do
    if MatchText(Directive, KeptDirectives) then
      Result := Result + ' ' + Directive + ';';
  Result := Result + ' ' + AMiddle;
  for Directive in TMemberTransfer.DirectiveTexts(ALayout, ALayout.Members[AIndex].Node) do
    if MatchText(Directive.Split([' '])[0], HintDirectives) then
      Result := Result + ' ' + Directive + ';';
end;

class function TMemberTransfer.AbstractDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
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

class function TMemberTransfer.VirtualDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
begin
  Result := Rewritten(ALayout, AIndex, 'virtual;');
end;

class function TMemberTransfer.OverrideDeclaration(ALayout: TClassLayout; AIndex: Integer): string;
begin
  Result := Rewritten(ALayout, AIndex, 'override;');
end;

class function TMemberTransfer.MemberLines(ALayout: TClassLayout; AIndex: Integer): TArray<string>;
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
  // Aus einem class-var-Abschnitt: am Ziel ohne den Abschnitt, also mit class var davor.
  if (Member.Kind = TClassMemberKind.ClassVar) and not StartsText('class', TrimLeft(Result[High(Result)])) then
    Result[High(Result)] := ALayout.MemberIndent + 'class var ' + TrimLeft(Result[High(Result)]);
end;

class function TMemberTransfer.MemberText(ALayout: TClassLayout; AIndex: Integer): string;
var
  Line: string;
begin
  Result := '';
  for Line in MemberLines(ALayout, AIndex) do
  begin
    if Result <> '' then
      Result := Result + #10;
    if StartsStr(ALayout.MemberIndent, Line) then
      Result := Result + Copy(Line, Length(ALayout.MemberIndent) + 1, MaxInt)
    else
      Result := Result + TrimLeft(Line);
  end;
end;

class function TMemberTransfer.WithDoc(ALayout: TClassLayout; AIndex: Integer; const ADeclaration: string): string;
var
  Doc: string;
begin
  Result := '';
  for Doc in ALayout.DocLines(AIndex) do
    Result := Result + Doc + #10;
  Result := Result + ADeclaration;
end;

class function TMemberTransfer.UsedOutside(ALayout: TClassLayout; const AName: string): Boolean;
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

class function TMemberTransfer.Same(ALayout: TClassLayout; const AOld: TClassMember): Integer;
var
  Index: Integer;
begin
  for Index in ALayout.Find(AOld.Name) do
    if (ALayout.Members[Index].Kind = AOld.Kind) and
      (string.Join(',', ALayout.Members[Index].ParameterTypes) = string.Join(',', AOld.ParameterTypes)) then
      Exit(Index);
  Result := -1;
end;

class function TMemberTransfer.ParseLayout(const AText, AName: string; out ATree: TSyntaxTree): TClassLayout;
var
  Decl: TSyntaxNode;
begin
  ATree := TSyntaxTreeCache.Parse(AText);
  Decl := TClassLayout.DeclNamed(ATree, AName);
  if Decl = nil then
  begin
    FreeAndNil(ATree);
    Exit(nil);
  end;
  Result := TClassLayout.Read(ATree, AText, Decl);
end;

class function TMemberTransfer.EmptiedSections(ALayout: TClassLayout;
  const ARemoved: TArray<Integer>): TArray<TTextEdit>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(ALayout.Sections) do
    if (ALayout.Sections[Index].HeadLine >= 0) and (ALayout.Sections[Index].Members <> nil) and
      HasAll(ALayout.Sections[Index].Members, ARemoved) then
      Result := Result + [TTextEdit.Create(LinesRange(ALayout.Sections[Index].HeadLine,
        ALayout.Sections[Index].HeadLine), '')];
end;

class function TMemberTransfer.Relocate(var AText: string; const AClassName: string;
  const AMembers: TArray<TClassMember>; AVisibility: TClassVisibility): Boolean;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Old: TClassMember;
  Index: Integer;
  Chosen: TArray<Integer>;
  Edits: TArray<TTextEdit>;
  Declarations: TArray<TTransferDeclaration>;
  Reason: string;
begin
  if AMembers = nil then
    Exit(True);
  Layout := ParseLayout(AText, AClassName, Tree);
  if Layout = nil then
    Exit(False);
  try
    Edits := nil;
    Declarations := nil;
    Chosen := nil;
    for Old in AMembers do
    begin
      Index := Same(Layout, Old);
      if (Index < 0) or (Layout.Members[Index].Visibility = AVisibility) then
        Continue;
      Chosen := Chosen + [Index];
      Declarations := Declarations + [TTransferDeclaration.Create(MemberText(Layout, Index), AVisibility,
        Layout.Members[Index].Kind in [TClassMemberKind.Field, TClassMemberKind.ClassVar])];
    end;
    if Declarations = nil then
      Exit(True);
    Edits := TClassEdits.DeleteMembers(Layout, Chosen, False) + EmptiedSections(Layout, Chosen);
    AText := TTextChanges.Apply(AText, Edits);
  finally
    Layout.Free;
    Tree.Free;
  end;
  // Felder vor Methoden, je Abschnitt neu geparst.
  Result := InsertInto(AText, AClassName, Declarations, nil, Reason);
end;

class function TMemberTransfer.InsertInto(var AText: string; const AClassName: string;
  const ADeclarations: TArray<TTransferDeclaration>; const ABodies: TArray<string>; out AReason: string): Boolean;
var
  Layout: TClassLayout;
  Tree: TSyntaxTree;
  Visibility: TClassVisibility;
  Fields, Others: TArray<string>;
  Item: TTransferDeclaration;
  Section: TClassSection;
  Exists: Boolean;
  Pass, Line: Integer;
begin
  AReason := '';
  Layout := ParseLayout(AText, AClassName, Tree);
  if Layout = nil then
  begin
    AReason := Format('Die Klasse %s ist nicht lesbar.', [AClassName]);
    Exit(False);
  end;
  Layout.Free;
  Tree.Free;
  // Je Sichtbarkeit einzeln und neu geparst: Zwei neue Abschnitte an derselben Stelle wären sonst ungeordnet.
  for Visibility := Low(TClassVisibility) to High(TClassVisibility) do
  begin
    Fields := nil;
    Others := nil;
    for Item in ADeclarations do
      if (Item.Visibility = Visibility) and Item.IsField then
        Fields := Fields + [Item.Text]
      else if Item.Visibility = Visibility then
        Others := Others + [Item.Text];
    if (Fields = nil) and (Others = nil) then
      Continue;
    for Pass := 0 to 1 do
    begin
      Layout := ParseLayout(AText, AClassName, Tree);
      if Layout = nil then
      begin
        AReason := Format('Die Klasse %s ist nicht mehr lesbar.', [AClassName]);
        Exit(False);
      end;
      try
        Exists := False;
        for Section in Layout.Sections do
          if Section.Visibility = Visibility then
            Exists := True;
        // Ohne Abschnitt entsteht einer: Felder und Methoden zusammen (Felder vorn).
        if not Exists then
        begin
          AText := TTextChanges.Apply(AText, [TClassEdits.InsertMembers(Layout, Visibility, Fields <> nil,
            Fields + Others)]);
          Break;
        end;
        if (Pass = 0) and (Fields <> nil) then
          AText := TTextChanges.Apply(AText, [TClassEdits.InsertMembers(Layout, Visibility, True, Fields)])
        else if (Pass = 1) and (Others <> nil) then
          AText := TTextChanges.Apply(AText, [TClassEdits.InsertMembers(Layout, Visibility, False, Others)]);
      finally
        Layout.Free;
        Tree.Free;
      end;
    end;
  end;
  if ABodies <> nil then
  begin
    Tree := TSyntaxTreeCache.Parse(AText);
    try
      Line := TClassEdits.BodiesEnd(Tree, AClassName);
      if Line < 0 then
      begin
        AReason := Format('Die Unit von %s hat keinen implementation-Teil für die Rümpfe.', [AClassName]);
        Exit(False);
      end;
      AText := TTextChanges.Apply(AText, [TClassEdits.InsertBodies(AText, Line, ABodies)]);
    finally
      Tree.Free;
    end;
  end;
  Result := True;
end;

end.
