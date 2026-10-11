unit Atlas.Common.Rules.Builtin.FormFields;

// Abgleich von Formularklasse und Formulardatei (#123):
//   form-field-without-object   published-Feld ohne Objekt in der .dfm/.fmx
//   form-object-without-field   Objekt der Formulardatei ohne Feld in der Klasse
//   form-field-type-mismatch    Feld und Objekt mit verschiedener Klasse
//
// Die Formulardatei neben der Unit kommt über TRuleContext.FormText; ohne sie
// prüfen die Regeln nichts. Geerbte Objekte (inherited) gehören zu Feldern des
// Vorfahren, Objekte in inline-Frames zur Frame-Klasse, Komponenten ohne Namen
// und Collection-Einträge haben kein Feld; sie werden nicht gemeldet. Felder
// außerhalb von published zählen nicht als fehlende Objekte. Kennt der
// Symbolindex die Klasse aus der Formulardatei nicht, entfällt der Typvergleich.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TFormFieldWithoutObjectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormObjectWithoutFieldRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TFormFieldTypeMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterFormFieldRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser;

type
  TFormField = record
    Name: string;
    TypeName: string;
    Node: TSyntaxNode;
    TypeNode: TSyntaxNode;
    IsPublished: Boolean;
  end;

  /// <summary>Formularklasse der Unit und Objekte der Formulardatei.</summary>
  TFormMatch = class
  private
    FDocument: TDfmDocument;
    FClass: TSyntaxNode;
    FFields: TList<TFormField>;
    FObjects: TList<TDfmObject>;
    procedure CollectObjects(AObject: TDfmObject; AInFrame: Boolean);
    function FindClass(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    function Valid: Boolean;
    function FindField(const AName: string; out AField: TFormField): Boolean;
    /// <summary>Hat die Formulardatei irgendein Objekt dieses Namens (auch inherited)?</summary>
    function HasObject(const AName: string): Boolean;
    /// <summary>Einfügestelle für ein neues Feld: vor dem ersten Sichtbarkeitsabschnitt.</summary>
    function FieldInsert(const AText: string; out ALine: Integer; out AIndent: string): Boolean;
    property Fields: TList<TFormField> read FFields;
    /// <summary>Eigene Objekte des Formulars: benannt, nicht geerbt, nicht in Frames.</summary>
    property Objects: TList<TDfmObject> read FObjects;
    property Document: TDfmDocument read FDocument;
  end;

function ShortName(const AName: string): string;
begin
  Result := AName;
  if LastDelimiter('.', Result) > 0 then
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TFormMatch }

constructor TFormMatch.Create(const AContext: TRuleContext);
var
  Index: Integer;
  Child: TSyntaxNode;
  Field: TFormField;
  IsPublished: Boolean;
begin
  inherited Create;
  FFields := TList<TFormField>.Create;
  FObjects := TList<TDfmObject>.Create;
  if (AContext.FormText = '') or (AContext.Tree = nil) then
    Exit;
  FDocument := TDfmParser.Parse(AContext.FormText);
  if FDocument.Root = nil then
    Exit;
  FClass := FindClass(AContext.Tree.Root, FDocument.Root.TypeName);
  if FClass = nil then
    Exit;
  // Ohne Sichtbarkeit gilt published (Formulare werden mit {$M+} übersetzt).
  IsPublished := True;
  for Index := 0 to FClass.ChildCount - 1 do
  begin
    Child := FClass.Children[Index];
    if Child.Kind = TSyntaxKind.Visibility then
      IsPublished := SameText(Child.Name, 'published')
    else if (Child.Kind = TSyntaxKind.Field) and (Child.Name <> '') then
    begin
      Field := Default(TFormField);
      Field.Name := Child.Name;
      Field.Node := Child;
      Field.TypeNode := Child.FindChild(TSyntaxKind.TypeReference);
      if Field.TypeNode <> nil then
        Field.TypeName := Field.TypeNode.Name;
      Field.IsPublished := IsPublished;
      FFields.Add(Field);
    end;
  end;
  CollectObjects(FDocument.Root, False);
end;

destructor TFormMatch.Destroy;
begin
  FObjects.Free;
  FFields.Free;
  FDocument.Free;
  inherited;
end;

function TFormMatch.FindClass(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
    Exit(ANode.FindChild(TSyntaxKind.ClassType));
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
      TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection,
      TSyntaxKind.TypeDecl] then
    begin
      Result := FindClass(ANode.Children[Index], AName);
      if Result <> nil then
        Exit;
    end;
  Result := nil;
end;

procedure TFormMatch.CollectObjects(AObject: TDfmObject; AInFrame: Boolean);
var
  Child: TDfmObject;
begin
  if (AObject <> FDocument.Root) and not AInFrame and (AObject.Name <> '') and
    (AObject.Kind in [TDfmObjectKind.Object_, TDfmObjectKind.Inline_]) then
    FObjects.Add(AObject);
  for Child in AObject.Children do
    CollectObjects(Child, AInFrame or ((AObject <> FDocument.Root) and (AObject.Kind = TDfmObjectKind.Inline_)));
end;

function TFormMatch.Valid: Boolean;
begin
  Result := FClass <> nil;
end;

function TFormMatch.FindField(const AName: string; out AField: TFormField): Boolean;
var
  Field: TFormField;
begin
  for Field in FFields do
    if SameText(Field.Name, AName) then
    begin
      AField := Field;
      Exit(True);
    end;
  Result := False;
end;

function SearchObject(AObject: TDfmObject; const AName: string): Boolean;
var
  Child: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
    Exit(True);
  for Child in AObject.Children do
    if SearchObject(Child, AName) then
      Exit(True);
  Result := False;
end;

function TFormMatch.HasObject(const AName: string): Boolean;
begin
  Result := SearchObject(FDocument.Root, AName);
end;

function LineIndent(const AText: string; ALine: Integer): string;
var
  Index, Line: Integer;
begin
  Result := '';
  // Anfang der Zeile ALine suchen.
  Index := 1;
  Line := 0;
  while (Line < ALine) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
    Inc(Index);
  end;
  while (Index <= Length(AText)) and CharInSet(AText[Index], [' ', #9]) do
  begin
    Result := Result + AText[Index];
    Inc(Index);
  end;
end;

function TFormMatch.FieldInsert(const AText: string; out ALine: Integer; out AIndent: string): Boolean;
var
  Index: Integer;
  First: TSyntaxNode;
begin
  // Vor dem ersten Sichtbarkeitsabschnitt, sonst vor dem end der Klasse.
  ALine := FClass.EndPos.Line;
  First := nil;
  for Index := 0 to FClass.ChildCount - 1 do
    if FClass.Children[Index].Kind = TSyntaxKind.Visibility then
    begin
      ALine := FClass.Children[Index].StartPos.Line;
      Break;
    end
    else if (First = nil) and (FClass.Children[Index].Kind in [TSyntaxKind.Field, TSyntaxKind.RoutineHeader,
      TSyntaxKind.PropertyDecl]) then
      First := FClass.Children[Index];
  if First <> nil then
    AIndent := LineIndent(AText, First.StartPos.Line)
  else
    AIndent := LineIndent(AText, ALine) + '  ';
  Result := ALine > FClass.StartPos.Line;
end;

function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

{ TFormFieldWithoutObjectRule }

function TFormFieldWithoutObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-without-object', TRuleSeverity.Warning,
    'Komponentenfeld des Formulars ohne Objekt in der Formulardatei');
end;

procedure TFormFieldWithoutObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Field: TFormField;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
      Exit;
    for Field in Match.Fields do
      if Field.IsPublished and not Match.HasObject(Field.Name) then
        AReport.Add(NodeRange(Field.Node), Format('Feld %s hat kein Objekt in der Formulardatei; beim Laden ' +
          'bleibt es nil', [Field.Name]));
  finally
    Match.Free;
  end;
end;

{ TFormObjectWithoutFieldRule }

function TFormObjectWithoutFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-object-without-field', TRuleSeverity.Warning,
    'Objekt der Formulardatei ohne Feld in der Formularklasse');
end;

procedure TFormObjectWithoutFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Obj: TDfmObject;
  Field: TFormField;
  Line: Integer;
  Indent: string;
  Fixes: TArray<TRuleFix>;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
      Exit;
    for Obj in Match.Objects do
      if not Match.FindField(Obj.Name, Field) then
      begin
        Fixes := nil;
        if Match.FieldInsert(AContext.Text, Line, Indent) then
          Fixes := [TRuleFix.Create(Format('Feld %s: %s ergänzen', [Obj.Name, Obj.TypeName]),
            [TRuleEdit.Create(TTextRange.Create(Line, 0, Line, 0),
            Indent + Obj.Name + ': ' + Obj.TypeName + ';' + LineBreakOf(AContext.Text))])];
        // Gemeldet wird an der Formularklasse; die Formulardatei ist nicht das geprüfte Dokument.
        AReport.Add(TTextRange.Create(Match.FClass.Parent.StartPos.Line, Match.FClass.Parent.StartPos.Character,
          Match.FClass.Parent.StartPos.Line, Match.FClass.Parent.StartPos.Character +
          Length(Match.FClass.Parent.Name)), Format('Objekt %s: %s der Formulardatei hat kein Feld ' +
          'in %s', [Obj.Name, Obj.TypeName, Match.Document.Root.TypeName]), Fixes);
      end;
  finally
    Match.Free;
  end;
end;

{ TFormFieldTypeMismatchRule }

function TFormFieldTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-type-mismatch', TRuleSeverity.Warning,
    'Feld und Objekt der Formulardatei haben verschiedene Klassen');
end;

function KnownClass(const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  Location: TSymbolLocation;
begin
  if AIndex = nil then
    Exit(True);
  for Location in AIndex.FindSymbols(ShortName(AName)) do
    if Location.Symbol.Kind = TIndexSymbolKind.ClassType then
      Exit(True);
  Result := False;
end;

procedure TFormFieldTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Match: TFormMatch;
  Obj: TDfmObject;
  Field: TFormField;
begin
  Match := TFormMatch.Create(AContext);
  try
    if not Match.Valid then
      Exit;
    for Obj in Match.Objects do
      if Match.FindField(Obj.Name, Field) and (Field.TypeNode <> nil) and
        not SameText(ShortName(Field.TypeName), ShortName(Obj.TypeName)) and KnownClass(AContext.Index, Obj.TypeName) then
        AReport.Add(NodeRange(Field.TypeNode), Format('Feld %s ist %s, das Objekt in der Formulardatei aber %s',
          [Field.Name, Field.TypeName, Obj.TypeName]),
          [TRuleFix.Create(Format('Typ auf %s ändern', [Obj.TypeName]),
          [TRuleEdit.Create(NodeRange(Field.TypeNode), Obj.TypeName)])]);
  finally
    Match.Free;
  end;
end;

procedure RegisterFormFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormFieldWithoutObjectRule.Create);
  ARegistry.Register(TFormObjectWithoutFieldRule.Create);
  ARegistry.Register(TFormFieldTypeMismatchRule.Create);
end;

end.
