unit Atlas.Common.Rules.Builtin.Style.Declarations;

// Stilregeln zu Deklarationen, registriert mit den übrigen Stilregeln (RegisterStyleRules):
//   public-field     Feld im public- oder published-Abschnitt einer Klasse (Standard aus, #940); Records nur mit
//                    includeRecords. Der Abschnitt ohne Sichtbarkeitswort zählt nur bei Klassen ohne Vorfahren bzw.
//                    mit TObject: sonst stehen dort die Felder des Designers. Korrektur „Feld kapseln“: FName im
//                    private-Abschnitt am Ende der Klasse, dazu property Name read FName write FName (wie
//                    /encapsulate, #298)
//   global-variable  var bzw. threadvar im interface-Teil einer Unit (Standard aus, #941); die Formularvariable des
//                    Designers (frmHaupt: TfrmHaupt) nur mit includeFormVariables

interface

uses
  Atlas.Common.Rules.Contract;

type
  TPublicFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TGlobalVariableRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStyleDeclarationsText = (PublicFieldTitle, Encapsulate, PublicField, GlobalTitle, Global);

const
  cTexts: array[TStyleDeclarationsText] of TAtlasText = (
    (De: 'Öffentliches Feld'; En: 'Public field'),
    (De: 'Feld kapseln'; En: 'Encapsulate field'),
    (De: 'Öffentliches Feld %s; eine Property hält die Klasse änderbar.';
     En: 'Public field %s; a property keeps the class changeable.'),
    (De: 'Globale Variable im interface'; En: 'Global variable in the interface'),
    (De: 'Globale Variable %s ist in jeder Unit sichtbar, die diese verwendet.';
     En: 'Global variable %s is visible in every unit that uses this one.'));

{$SCOPEDENUMS OFF}

{ TPublicFieldRule }

function TPublicFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('public-field', TRuleSeverity.Hint,
    cTexts[TStyleDeclarationsText.PublicFieldTitle].Text, True);
end;

procedure TPublicFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;
  IncludeRecords: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function LineOf(ALine: Integer): string;
  begin
    Result := '';
    if (ALine >= 0) and (ALine <= High(Lines)) then
    begin
      Result := Lines[ALine];
    end;
  end;

  // Steht ANode allein in seiner Zeile (nur Leerraum davor und dahinter)?
  function AloneInLine(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.StartPos.Line = ANode.EndPos.Line) and
      (Trim(Copy(LineOf(ANode.StartPos.Line), 1, ANode.StartPos.Character)) = '') and
      (Trim(Copy(LineOf(ANode.EndPos.Line), ANode.EndPos.Character + 1, MaxInt)) = '');
  end;

  function HasMember(AType: TSyntaxNode; const AName: string): Boolean;
  var
    Index: Integer;
    Name: string;
  begin
    for Index := 0 to AType.ChildCount - 1 do
    begin
      if AType[Index].Kind in [TSyntaxKind.Field, TSyntaxKind.PropertyDecl, TSyntaxKind.RoutineHeader] then
      begin
        for Name in AType[Index].Name.Split([',']) do
        begin
          if SameText(Trim(Name), AName) then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
    Result := False;
  end;

  function FieldNameOf(const AName: string): string;
  begin
    Result := 'F' + UpperCase(Copy(AName, 1, 1)) + Copy(AName, 2, MaxInt);
  end;

  // Name mit F-Präfix: Die Property hieße anders als das Feld; Zugriffe von außen gingen verloren.
  function Prefixed(const AName: string): Boolean;
  begin
    Result := (Length(AName) >= 2) and CharInSet(AName[1], ['F', 'f']) and CharInSet(AName[2], ['A'..'Z']);
  end;

  // Ein Name allein in seiner Zeile, mit Typ, ohne F-Präfix, FName noch frei und end des Typs am Zeilenanfang.
  function Encapsulable(AType, AField: TSyntaxNode): Boolean;
  var
    Name: string;
  begin
    Name := Trim(AField.Name);
    Result := (Pos(',', Name) = 0) and (AField.FindChild(TSyntaxKind.TypeReference) <> nil) and AloneInLine(AField);
    Result := Result and not Prefixed(Name) and not HasMember(AType, FieldNameOf(Name));
    Result := Result and (Trim(Copy(LineOf(AType.EndPos.Line), 1, AType.EndPos.Character - 3)) = '');
  end;

  function IndexOfChild(AParent, AChild: TSyntaxNode): Integer;
  begin
    for Result := 0 to AParent.ChildCount - 1 do
    begin
      if AParent[Result] = AChild then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // Einziges Mitglied seines Abschnitts: Das Sichtbarkeitswort geht mit.
  function SectionEdits(AType, AField, ASection: TSyntaxNode): TArray<TTextEdit>;
  var
    Position: Integer;
    Next: TSyntaxNode;
  begin
    Result := nil;
    if (ASection = nil) or not AloneInLine(ASection) then
    begin
      Exit;
    end;
    Position := IndexOfChild(AType, AField);
    Next := nil;
    if (Position >= 0) and (Position < AType.ChildCount - 1) then
    begin
      Next := AType[Position + 1];
    end;
    if (Position > 0) and (AType[Position - 1] = ASection) and ((Next = nil) or (Next.Kind = TSyntaxKind.Visibility))
      then
    begin
      Result := [TTextEdit.Create(TTextRange.Create(ASection.StartPos.Line, 0, ASection.StartPos.Line + 1, 0), '')];
    end;
  end;

  // private-Abschnitt mit FName und die Property im alten Abschnitt, vor dem end des Typs.
  function MemberText(const AName, ATypeName, AIndent, AVisibility: string): string;
  var
    FieldName: string;
  begin
    FieldName := FieldNameOf(AName);
    Result := AIndent + 'private' + LineBreak + AIndent + '  ' + FieldName + ': ' + ATypeName + ';' + LineBreak +
      AIndent + AVisibility + LineBreak + AIndent + '  property ' + AName + ': ' + ATypeName + ' read ' + FieldName +
      ' write ' + FieldName + ';' + LineBreak;
  end;

  // FName in private am Ende des Typs, Property im alten Abschnitt; der leere Abschnitt fällt weg.
  function Encapsulate(AType, AField, ASection: TSyntaxNode; const AVisibility: string;
    out AFix: TRuleFix): Boolean;
  var
    Name, TypeName, Indent: string;
    EndLine: Integer;
    Edits: TArray<TTextEdit>;
  begin
    Result := Encapsulable(AType, AField);
    if not Result then
    begin
      Exit;
    end;
    Name := Trim(AField.Name);
    TypeName := NodeText(AField.FindChild(TSyntaxKind.TypeReference));
    EndLine := AType.EndPos.Line;
    Indent := TTextLines.IndentOf(LineOf(EndLine));
    Edits := SectionEdits(AType, AField, ASection);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(AField.StartPos.Line, 0, AField.StartPos.Line + 1, 0), '')];
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(EndLine, 0, EndLine, 0), MemberText(Name, TypeName, Indent,
      AVisibility))];
    AFix := TRuleFix.Create(cTexts[TStyleDeclarationsText.Encapsulate].Text, Edits);
  end;

  // Zählt ein Feld im Abschnitt AVisibility ('' = ohne Sichtbarkeitswort)?
  function FieldCounts(const AVisibility: string; AImplicitCounts: Boolean): Boolean;
  begin
    if AVisibility = '' then
    begin
      Result := AImplicitCounts;
    end
    else
    begin
      Result := MatchText(AVisibility, ['public', 'published']);
    end;
  end;

  function FieldFixes(AType, AField, ASection: TSyntaxNode; const AVisibility, AImplicit: string): TArray<TRuleFix>;
  var
    Fix: TRuleFix;
    Encapsulated: Boolean;
  begin
    if AVisibility = '' then
    begin
      Encapsulated := Encapsulate(AType, AField, nil, AImplicit, Fix);
    end
    else
    begin
      Encapsulated := Encapsulate(AType, AField, ASection, AVisibility, Fix);
    end;
    Result := nil;
    if Encapsulated then
    begin
      Result := [Fix];
    end;
  end;

  procedure CheckType(AType: TSyntaxNode; AImplicitCounts: Boolean; const AImplicit: string);
  var
    Index: Integer;
    Child, Section: TSyntaxNode;
    Visibility, Name: string;
    Fixes: TArray<TRuleFix>;
  begin
    Visibility := '';
    Section := nil;
    for Index := 0 to AType.ChildCount - 1 do
    begin
      Child := AType[Index];
      if Child.Kind = TSyntaxKind.Visibility then
      begin
        Visibility := Child.Name;
        Section := Child;
        Continue;
      end;
      if (Child.Kind <> TSyntaxKind.Field) or not FieldCounts(Visibility, AImplicitCounts) then
      begin
        Continue;
      end;
      Fixes := FieldFixes(AType, Child, Section, Visibility, AImplicit);
      for Name in Child.Name.Split([',']) do
      begin
        AReport.Add(TTextRange.Create(Child.StartPos, Child.EndPos),
          cTexts[TStyleDeclarationsText.PublicField].Fmt([Trim(Name)]), Fixes);
      end;
    end;
  end;

  // Abschnitt ohne Sichtbarkeitswort: bei Klassen ohne Vorfahren public, sonst oft Felder des Designers.
  function PlainClass(AClass: TSyntaxNode): Boolean;
  var
    Ancestor: TSyntaxNode;
  begin
    Ancestor := AClass.FindChild(TSyntaxKind.TypeReference);
    Result := (Ancestor = nil) or SameText(NodeText(Ancestor), 'TObject');
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.ClassType:
            CheckType(Node, PlainClass(Node), 'public');
          TSyntaxKind.RecordType:
            if IncludeRecords then
            begin
              CheckType(Node, True, 'public');
            end;
          TSyntaxKind.Block, TSyntaxKind.AsmBlock:
            Continue;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  IncludeRecords := TRuleOptions.Bool(AContext.Options, 'includeRecords', False);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root);
end;

{ TGlobalVariableRule }

function TGlobalVariableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('global-variable', TRuleSeverity.Hint,
    cTexts[TStyleDeclarationsText.GlobalTitle].Text, True);
end;

procedure TGlobalVariableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  FormRoots: array[0..7] of string = ('TForm', 'TCustomForm', 'TFrame', 'TCustomFrame', 'TDataModule',
    'TService', 'TWebModule', 'TCustomDataModule');
var
  Tokens: TArray<TPascalToken>;
  FormClasses: TArray<string>;
  IncludeForms: Boolean;

  function NodeText(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  // Klasse mit Vorfahren in einer Unit mit Formulardatei bzw. direkter Nachfahre einer bekannten Designerklasse?
  function IsFormClass(ATypeDecl: TSyntaxNode): Boolean;
  var
    Body, Ancestor: TSyntaxNode;
  begin
    Result := False;
    Body := ATypeDecl.FindChild(TSyntaxKind.ClassType);
    if Body = nil then
    begin
      Exit;
    end;
    Ancestor := Body.FindChild(TSyntaxKind.TypeReference);
    Result := (Ancestor <> nil) and ((AContext.FormText <> '') or MatchText(NodeText(Ancestor), FormRoots));
  end;

  // Klassen der Unit, die ein Formular, Frame oder Datenmodul sind: mit Formulardatei jede Klasse mit
  // Vorfahren, sonst die direkten Nachfahren bekannter Designerklassen.
  procedure CollectForms(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.TypeDecl then
        begin
          if IsFormClass(Node) then
          begin
            FormClasses := FormClasses + [Node.Name];
          end;
          Continue;
        end;
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.RoutineDecl] then
        begin
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function NameRange(ADecl: TSyntaxNode; const AName: string): TTextRange;
  var
    Index: Integer;
  begin
    Result := TTextRange.Create(ADecl.StartPos, ADecl.EndPos);
    // Nur die Token der Deklaration, binär angesprungen statt die ganze Datei (#1342).
    Index := TSyntaxTree.FirstTokenOf(Tokens, ADecl.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < ADecl.EndOffset) do
    begin
      if (Tokens[Index].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[Index].Text, AName) then
      begin
        Exit(TTextRange.Create(Tokens[Index].StartPos, Tokens[Index].EndPos));
      end;
      Inc(Index);
    end;
  end;

  procedure CheckSection(ASection: TSyntaxNode);
  var
    Index: Integer;
    Decl, TypeRef: TSyntaxNode;
    Name: string;
  begin
    for Index := 0 to ASection.ChildCount - 1 do
    begin
      Decl := ASection[Index];
      if Decl.Kind <> TSyntaxKind.VarDecl then
      begin
        Continue;
      end;
      TypeRef := Decl.FindChild(TSyntaxKind.TypeReference);
      if not IncludeForms and (TypeRef <> nil) and MatchText(NodeText(TypeRef), FormClasses) then
      begin
        Continue;
      end;
      for Name in Decl.Name.Split([',']) do
      begin
        AReport.Add(NameRange(Decl, Trim(Name)), cTexts[TStyleDeclarationsText.Global].Fmt([Trim(Name)]));
      end;
    end;
  end;

var
  InterfacePart: TSyntaxNode;
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  InterfacePart := AContext.Tree.Root.FindChild(TSyntaxKind.InterfaceSection);
  if InterfacePart = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  IncludeForms := TRuleOptions.Bool(AContext.Options, 'includeFormVariables', False);
  FormClasses := nil;
  CollectForms(InterfacePart);
  for Index := 0 to InterfacePart.ChildCount - 1 do
  begin
    if InterfacePart[Index].Kind = TSyntaxKind.VarSection then
    begin
      CheckSection(InterfacePart[Index]);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Style.Declarations', cTexts);

end.
