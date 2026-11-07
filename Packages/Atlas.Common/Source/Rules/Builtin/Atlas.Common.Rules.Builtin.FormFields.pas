unit Atlas.Common.Rules.Builtin.FormFields;

// Abgleich von Formularklasse und Formulardatei (#123):
//   form-field-without-object   published-Feld ohne Objekt in der .dfm/.fmx
//   form-object-without-field   Objekt der Formulardatei ohne Feld in der Klasse
//   form-field-type-mismatch    Feld und Objekt mit verschiedener Klasse
//   form-access-before-create   Konstruktor, AfterConstruction oder OnCreate eines automatisch erzeugten
//                               Formulars benutzt die globale Variable eines Formulars, das laut
//                               Application.CreateForm in der .dpr erst danach entsteht (#956). Die
//                               Reihenfolge kommt über TRuleContext.AutoCreateForms vom Server. Still bei
//                               Assigned/nil-Vergleich, eigener Zuweisung, CreateForm und lokalen Namen.
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

  TFormAccessBeforeCreateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Variablen aus Application.CreateForm(TKlasse, Variable) der .dpr in Aufrufreihenfolge.</summary>
    class function AutoCreatedForms(const AMainSource: string): TArray<string>; static;
    /// <summary>AutoCreatedForms des ersten Programms aus APrograms (Quelltexte der .dpr), dessen uses die Unit
    /// AUnitName nennt; nil ohne (Linter, Golden-Korpus).</summary>
    class function FormsOfProgram(const APrograms: TArray<string>; const AUnitName: string): TArray<string>; static;
    /// <summary>Name des OnCreate-Handlers des Formulars selbst aus der Formulardatei; '' ohne.</summary>
    class function CreateHandler(const AFormText: string): string; static;
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
  Atlas.Common.Dfm.Parser,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFormFieldsText = (NoObjectTitle, NoObject, NoFieldTitle, AddField, NoField, ClassTitle, ClassDiffers, ChangeType,
    NotCreatedTitle, NotCreated);

const
  cTexts: array[TFormFieldsText] of TAtlasText = (
    (De: 'Komponentenfeld des Formulars ohne Objekt in der Formulardatei';
     En: 'Component field of the form without an object in the form file'),
    (De: 'Feld %s hat kein Objekt in der Formulardatei; beim Laden bleibt es nil';
     En: 'Field %s has no object in the form file; it stays nil after loading'),
    (De: 'Objekt der Formulardatei ohne Feld in der Formularklasse';
     En: 'Object of the form file without a field in the form class'),
    (De: 'Feld %s: %s ergänzen'; En: 'Add field %s: %s'),
    (De: 'Objekt %s: %s der Formulardatei hat kein Feld in %s';
     En: 'Object %s: %s of the form file has no field in %s'),
    (De: 'Feld und Objekt der Formulardatei haben verschiedene Klassen';
     En: 'Field and object of the form file have different classes'),
    (De: 'Feld %s ist %s, das Objekt in der Formulardatei aber %s';
     En: 'Field %s is %s, but the object in the form file is %s'),
    (De: 'Typ auf %s ändern'; En: 'Change type to %s'),
    (De: 'Zugriff auf ein Formular, das noch nicht erzeugt ist'; En: 'Access to a form that is not created yet'),
    (De: '%s wird in der .dpr erst nach %s erzeugt und ist hier noch nil.';
     En: '%s is created in the .dpr only after %s and is still nil here.'));

{$SCOPEDENUMS OFF}

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
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

{ TFormMatch }

constructor TFormMatch.Create(const AContext: TRuleContext);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mField: TFormField;
  mIsPublished: Boolean;
begin
  inherited Create;
  FFields := TList<TFormField>.Create;
  FObjects := TList<TDfmObject>.Create;
  if (AContext.FormText = '') or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  FDocument := TDfmParser.Parse(AContext.FormText);
  if FDocument.Root = nil then
  begin
    Exit;
  end;
  FClass := FindClass(AContext.Tree.Root, FDocument.Root.TypeName);
  if FClass = nil then
  begin
    Exit;
  end;
  // Ohne Sichtbarkeit gilt published (Formulare werden mit {$M+} übersetzt).
  mIsPublished := True;
  for mIndex := 0 to FClass.ChildCount - 1 do
  begin
    mChild := FClass.Children[mIndex];
    if mChild.Kind = TSyntaxKind.Visibility then
    begin
      mIsPublished := SameText(mChild.Name, 'published');
    end
    else if (mChild.Kind = TSyntaxKind.Field) and (mChild.Name <> '') then
    begin
      mField := Default(TFormField);
      mField.Name := mChild.Name;
      mField.Node := mChild;
      mField.TypeNode := mChild.FindChild(TSyntaxKind.TypeReference);
      if mField.TypeNode <> nil then
      begin
        mField.TypeName := mField.TypeNode.Name;
      end;
      mField.IsPublished := mIsPublished;
      FFields.Add(mField);
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

// Iterativ (Bericht M1).
function TFormMatch.FindClass(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, AName) then
      begin
        Result := mNode.FindChild(TSyntaxKind.ClassType);
        if Result <> nil then
        begin
          Exit;
        end;
        Continue;
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode.Children[mIndex].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.LibraryFile,
          TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection,
          TSyntaxKind.TypeDecl] then
        begin
          mPending.Push(mNode.Children[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TFormMatch.CollectObjects(AObject: TDfmObject; AInFrame: Boolean);
var
  mChild: TDfmObject;
begin
  if (AObject <> FDocument.Root) and not AInFrame and (AObject.Name <> '') and
    (AObject.Kind in [TDfmObjectKind.Object_, TDfmObjectKind.Inline_]) then
  begin
    FObjects.Add(AObject);
  end;
  for mChild in AObject.Children do
  begin
    CollectObjects(mChild, AInFrame or ((AObject <> FDocument.Root) and (AObject.Kind = TDfmObjectKind.Inline_)));
  end;
end;

function TFormMatch.Valid: Boolean;
begin
  Result := FClass <> nil;
end;

function TFormMatch.FindField(const AName: string; out AField: TFormField): Boolean;
var
  mField: TFormField;
begin
  for mField in FFields do
  begin
    if SameText(mField.Name, AName) then
    begin
      AField := mField;
      Exit(True);
    end;
  end;
  Result := False;
end;

function SearchObject(AObject: TDfmObject; const AName: string): Boolean;
var
  mChild: TDfmObject;
begin
  if SameText(AObject.Name, AName) then
  begin
    Exit(True);
  end;
  for mChild in AObject.Children do
  begin
    if SearchObject(mChild, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TFormMatch.HasObject(const AName: string): Boolean;
begin
  Result := SearchObject(FDocument.Root, AName);
end;

function LineIndent(const AText: string; ALine: Integer): string;
var
  mIndex, mLine: Integer;
begin
  Result := '';
  // Anfang der Zeile ALine suchen.
  mIndex := 1;
  mLine := 0;
  while (mLine < ALine) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], [' ', #9]) do
  begin
    Result := Result + AText[mIndex];
    Inc(mIndex);
  end;
end;

function TFormMatch.FieldInsert(const AText: string; out ALine: Integer; out AIndent: string): Boolean;
var
  mIndex: Integer;
  mFirst: TSyntaxNode;
begin
  // Vor dem ersten Sichtbarkeitsabschnitt, sonst vor dem end der Klasse.
  ALine := FClass.EndPos.Line;
  mFirst := nil;
  for mIndex := 0 to FClass.ChildCount - 1 do
  begin
    if FClass.Children[mIndex].Kind = TSyntaxKind.Visibility then
    begin
      ALine := FClass.Children[mIndex].StartPos.Line;
      Break;
    end
    else if (mFirst = nil) and (FClass.Children[mIndex].Kind in [TSyntaxKind.Field, TSyntaxKind.RoutineHeader,
      TSyntaxKind.PropertyDecl]) then
    begin
      mFirst := FClass.Children[mIndex];
    end;
  end;
  if mFirst <> nil then
  begin
    AIndent := LineIndent(AText, mFirst.StartPos.Line);
  end
  else
  begin
    AIndent := LineIndent(AText, ALine) + '  ';
  end;
  Result := ALine > FClass.StartPos.Line;
end;

{ TFormFieldWithoutObjectRule }

function TFormFieldWithoutObjectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-without-object', TRuleSeverity.Warning,
    cTexts[TFormFieldsText.NoObjectTitle].Text);
end;

procedure TFormFieldWithoutObjectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMatch: TFormMatch;
  mField: TFormField;
begin
  mMatch := TFormMatch.Create(AContext);
  try
    if not mMatch.Valid then
    begin
      Exit;
    end;
    for mField in mMatch.Fields do
    begin
      if mField.IsPublished and not mMatch.HasObject(mField.Name) then
      begin
        AReport.Add(NodeRange(mField.Node), cTexts[TFormFieldsText.NoObject].Fmt([mField.Name]));
      end;
    end;
  finally
    mMatch.Free;
  end;
end;

{ TFormObjectWithoutFieldRule }

function TFormObjectWithoutFieldRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-object-without-field', TRuleSeverity.Warning,
    cTexts[TFormFieldsText.NoFieldTitle].Text);
end;

procedure TFormObjectWithoutFieldRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMatch: TFormMatch;
  mObj: TDfmObject;
  mField: TFormField;
  mLine: Integer;
  mIndent: string;
  mFixes: TArray<TRuleFix>;
begin
  mMatch := TFormMatch.Create(AContext);
  try
    if not mMatch.Valid then
    begin
      Exit;
    end;
    for mObj in mMatch.Objects do
    begin
      if not mMatch.FindField(mObj.Name, mField) then
      begin
        mFixes := nil;
        if mMatch.FieldInsert(AContext.Text, mLine, mIndent) then
        begin
          mFixes := [TRuleFix.Create(cTexts[TFormFieldsText.AddField].Fmt([mObj.Name, mObj.TypeName]),
            [TRuleEdit.Create(TTextRange.Create(mLine, 0, mLine, 0),
            mIndent + mObj.Name + ': ' + mObj.TypeName + ';' + TTextLines.LineBreakOf(AContext.Text))])];
        end;
        // Gemeldet wird an der Formularklasse; die Formulardatei ist nicht das geprüfte Dokument.
        AReport.Add(TTextRange.Create(mMatch.FClass.Parent.StartPos.Line, mMatch.FClass.Parent.StartPos.Character,
          mMatch.FClass.Parent.StartPos.Line, mMatch.FClass.Parent.StartPos.Character +
          Length(mMatch.FClass.Parent.Name)), cTexts[TFormFieldsText.NoField].Fmt([mObj.Name, mObj.TypeName,
            mMatch.Document.Root.TypeName]), mFixes);
      end;
    end;
  finally
    mMatch.Free;
  end;
end;

{ TFormFieldTypeMismatchRule }

function TFormFieldTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-field-type-mismatch', TRuleSeverity.Warning,
    cTexts[TFormFieldsText.ClassTitle].Text);
end;

function KnownClass(const AIndex: ISymbolIndex; const AName: string): Boolean;
var
  mLocation: TSymbolLocation;
begin
  if AIndex = nil then
  begin
    Exit(True);
  end;
  for mLocation in AIndex.FindSymbols(ShortName(AName)) do
  begin
    if mLocation.Symbol.Kind = TIndexSymbolKind.ClassType then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TFormFieldTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMatch: TFormMatch;
  mObj: TDfmObject;
  mField: TFormField;
begin
  mMatch := TFormMatch.Create(AContext);
  try
    if not mMatch.Valid then
    begin
      Exit;
    end;
    for mObj in mMatch.Objects do
    begin
      if mMatch.FindField(mObj.Name, mField) and (mField.TypeNode <> nil) and
        not SameText(ShortName(mField.TypeName), ShortName(mObj.TypeName)) and
          KnownClass(AContext.Index, mObj.TypeName) then
      begin
        AReport.Add(NodeRange(mField.TypeNode), cTexts[TFormFieldsText.ClassDiffers].Fmt(
          [mField.Name, mField.TypeName, mObj.TypeName]),
          [TRuleFix.Create(cTexts[TFormFieldsText.ChangeType].Fmt([mObj.TypeName]),
          [TRuleEdit.Create(NodeRange(mField.TypeNode), mObj.TypeName)])]);
      end;
    end;
  finally
    mMatch.Free;
  end;
end;

{ TFormAccessBeforeCreateRule }

function TFormAccessBeforeCreateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('form-access-before-create', TRuleSeverity.Warning,
    cTexts[TFormFieldsText.NotCreatedTitle].Text);
end;

class function TFormAccessBeforeCreateRule.AutoCreatedForms(const AMainSource: string): TArray<string>;
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mIndex, mPosition: Integer;

  function IsText(APosition: Integer; const AText: string): Boolean;
  begin
    Result := (APosition <= High(mCode)) and SameText(mTokens[mCode[APosition]].Text, AText);
  end;

  /// <summary>Steht ab APosition "Application.CreateForm(Klasse, Name)" mit einem Bezeichner als Name?</summary>
  function IsCreateForm(APosition: Integer): Boolean;
  begin
    Result := IsText(APosition, 'Application') and IsText(APosition + 1, '.') and
      IsText(APosition + 2, 'CreateForm') and IsText(APosition + 3, '(');
    Result := Result and IsText(APosition + 5, ',') and IsText(APosition + 7, ')') and
      (mTokens[mCode[APosition + 6]].Kind = TPascalTokenKind.Identifier);
  end;

begin
  Result := nil;
  mTokens := TPascalLexer.Tokenize(AMainSource);
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  // Application.CreateForm(TfrmHaupt, frmHaupt);
  for mPosition := 0 to High(mCode) - 7 do
  begin
    if IsCreateForm(mPosition) then
    begin
      Result := Result + [mTokens[mCode[mPosition + 6]].Text];
    end;
  end;
end;

class function TFormAccessBeforeCreateRule.FormsOfProgram(const APrograms: TArray<string>;
  const AUnitName: string): TArray<string>;
var
  mMain: string;
begin
  for mMain in APrograms do
  begin
    if MatchText(AUnitName, TUsesClauses.UsedUnits(TPascalLexer.Tokenize(mMain))) then
    begin
      Exit(AutoCreatedForms(mMain));
    end;
  end;
  Result := nil;
end;

class function TFormAccessBeforeCreateRule.CreateHandler(const AFormText: string): string;
var
  mLine, mText: string;
begin
  // OnCreate des Formulars bzw. Datenmoduls selbst: vor dem ersten eingerückten object.
  for mLine in TTextLines.SplitLines(AFormText) do
  begin
    mText := Trim(mLine);
    if (mLine <> TrimLeft(mLine)) and (StartsText('object ', mText) or StartsText('inherited ', mText) or
      StartsText('inline ', mText)) then
    begin
      Break;
    end;
    if StartsText('OnCreate = ', mText) then
    begin
      Exit(Trim(Copy(mText, Length('OnCreate = ') + 1, MaxInt)));
    end;
  end;
  Result := '';
end;

procedure TFormAccessBeforeCreateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mForms: TArray<string>;
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mOwnIndex: Integer;
  mOwnName, mOwnClass, mHandler: string;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function CodeAt(AOffset: Integer): Integer;
  var
    mHigh, mMiddle: Integer;
  begin
    // Binär statt ab Dateianfang mit einer Kopie je Token: Code steht nach Offset sortiert (#1342).
    Result := 0;
    mHigh := Length(mCode);
    while Result < mHigh do
    begin
      mMiddle := (Result + mHigh) div 2;
      if mTokens[mCode[mMiddle]].Offset < AOffset then
      begin
        Result := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
  end;

  function FormIndex(const AName: string): Integer;
  begin
    for Result := 0 to High(mForms) do
    begin
      if SameText(mForms[Result], AName) then
      begin
        Exit;
      end;
    end;
    Result := -1;
  end;

  // Globale Variable dieser Unit, die in der .dpr erzeugt wird und deren Klasse hier deklariert ist.
  function FindOwnForm: Boolean;
  var
    mLocal: TUnitIndex;
    mSymbol, mTypeSymbol: TIndexSymbol;
    mCache: IRuleDerivedCache;
  begin
    mCache := TRuleDerived.Open(AContext);
    mLocal := TRuleDerived.UnitIndex(mCache, AContext);
    for mSymbol in mLocal.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Variable) and (mSymbol.Container = '') and (FormIndex(mSymbol.Name) >= 0) then
      begin
        for mTypeSymbol in mLocal.Symbols do
        begin
          if (mTypeSymbol.Kind = TIndexSymbolKind.ClassType) and (mTypeSymbol.Container = '') and
            SameText(mTypeSymbol.Name, mSymbol.TypeName) then
          begin
            mOwnName := mSymbol.Name;
            mOwnClass := mTypeSymbol.Name;
            mOwnIndex := FormIndex(mSymbol.Name);
            Exit(True);
          end;
        end;
      end;
    end;
    Result := False;
  end;

  /// <summary>Deklariert ein Kind von ANode (Variable, Parameter, Konstante) den Namen AName?</summary>
  function ChildDeclares(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    mIndex: Integer;
    mName: string;
  begin
    for mIndex := 0 to ANode.ChildCount - 1 do
    begin
      if ANode[mIndex].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter,
        TSyntaxKind.ConstDecl] then
      begin
        for mName in SplitString(ANode[mIndex].Name, ',') do
        begin
          if SameText(Trim(mName), AName) then
          begin
            Exit(True);
          end;
        end;
      end;
    end;
    Result := False;
  end;

  // Deklariert die Routine AName selbst (Parameter, lokale Variable)? Iterativ (Bericht M1).
  function DeclaresLocally(ANode: TSyntaxNode; const AName: string): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := ChildDeclares(mNode, AName);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          if mNode[mIndex].Kind <> TSyntaxKind.Block then
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  /// <summary>Vergleicht der Name an APosition mit nil (= nil, &lt;&gt; nil)?</summary>
  function ComparedWithNil(APosition: Integer): Boolean;
  begin
    Result := (IsSym(APosition + 1, '<>') or IsSym(APosition + 1, '=')) and (APosition + 2 <= High(mCode)) and
      Token(APosition + 2).IsKeyword('nil');
  end;

  /// <summary>Prüft oder setzt der Name an APosition die Variable (Assigned, nil-Vergleich, Zuweisung,
  /// CreateForm)?</summary>
  function HandledAt(APosition: Integer): Boolean;
  begin
    Result := (IsSym(APosition - 1, '(') and IsName(APosition - 2, 'Assigned')) or IsSym(APosition + 1, ':=') or
      ComparedWithNil(APosition);
    Result := Result or (IsSym(APosition - 1, ',') and IsName(APosition - 4, 'CreateForm'));
  end;

  // Prüft oder setzt die Routine die Variable selbst (Assigned, nil-Vergleich, Zuweisung, CreateForm)?
  function Handled(AFirst, ALast: Integer; const AName: string): Boolean;
  var
    mPosition: Integer;
  begin
    for mPosition := AFirst to ALast do
    begin
      if IsName(mPosition, AName) and not IsSym(mPosition - 1, '.') and HandledAt(mPosition) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  procedure CheckRoutine(ARoutine: TSyntaxNode);
  var
    mFirst, mLast, mPosition, mIndex: Integer;
    mBody: TSyntaxNode;
    mReported: TArray<string>;
    mName: string;
  begin
    mBody := TRoutineBody.BodyOf(ARoutine);
    if mBody = nil then
    begin
      Exit;
    end;
    mFirst := CodeAt(mBody.StartOffset);
    mLast := CodeAt(mBody.EndOffset) - 1;
    mReported := nil;
    for mPosition := mFirst to mLast do
    begin
      if (Token(mPosition).Kind <> TPascalTokenKind.Identifier) or IsSym(mPosition - 1, '.') then
      begin
        Continue;
      end;
      mIndex := FormIndex(Token(mPosition).Text);
      if mIndex <= mOwnIndex then
      begin
        Continue;
      end;
      mName := mForms[mIndex];
      if MatchText(mName, mReported) or DeclaresLocally(ARoutine, mName) or Handled(mFirst, mLast, mName) then
      begin
        Continue;
      end;
      mReported := mReported + [mName];
      AReport.Add(TTextRange.Create(Token(mPosition).StartPos, Token(mPosition).EndPos),
        cTexts[TFormFieldsText.NotCreated].Fmt([mName, mOwnName]),
        TRuleConfidence.Medium);
    end;
  end;

  // Konstruktor, AfterConstruction und OnCreate-Handler der eigenen Klasse.
  function IsCreationMethod(ARoutine: TSyntaxNode): Boolean;
  var
    mMethod: string;
  begin
    Result := False;
    if not StartsText(mOwnClass + '.', ARoutine.Name) then
    begin
      Exit;
    end;
    mMethod := Copy(ARoutine.Name, Length(mOwnClass) + 2, MaxInt);
    if Pos('.', mMethod) > 0 then
    begin
      Exit;
    end;
    Result := SameText(mMethod, 'AfterConstruction') or SameText(mMethod, mHandler) or
      ((mHandler = '') and MatchText(mMethod, ['FormCreate', 'DataModuleCreate'])) or
      Token(CodeAt(ARoutine.StartOffset)).IsKeyword('constructor');
  end;

var
  mRoutines: TArray<TSyntaxNode>;
  mRoutine: TSyntaxNode;
  mIndex: Integer;
begin
  mForms := AContext.AutoCreateForms;
  if (Length(mForms) < 2) or (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  if not FindOwnForm then
  begin
    Exit;
  end;
  mHandler := CreateHandler(AContext.FormText);
  mRoutines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mRoutines := mRoutines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  for mRoutine in mRoutines do
  begin
    if IsCreationMethod(mRoutine) then
    begin
      CheckRoutine(mRoutine);
    end;
  end;
end;

procedure RegisterFormFieldRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TFormFieldWithoutObjectRule.Create);
  ARegistry.Register(TFormObjectWithoutFieldRule.Create);
  ARegistry.Register(TFormFieldTypeMismatchRule.Create);
  ARegistry.Register(TFormAccessBeforeCreateRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.FormFields', cTexts);

end.
