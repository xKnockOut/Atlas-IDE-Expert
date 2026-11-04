unit Atlas.Common.Rules.Builtin.DataBinding;

// Datenbindungsregeln für Formulardateien (#151) und Zugriff auf fremde Formulare:
//   dfm-circular-datasource          DataSource/MasterSource-Verknüpfungen bilden einen Kreis
//   dfm-master-without-fields        MasterSource ohne MasterFields
//   dfm-required-field-without-control  Pflichtfeld ohne sichtbares Eingabe-Control
//   dfm-control-field-type-mismatch  Control passt nicht zum Feldtyp (TDBEdit auf TBooleanField)
//   dfm-duplicate-binding            zwei Controls an demselben DataSource/DataField
//   foreign-form-control-access      Form2.Edit1.Text aus einer anderen Unit
//
// Die DFM-Regeln lesen TRuleContext.FormText (#123) und melden an der
// Formularklasse. Verweise auf andere Module (DataSource = DM.dsKunden) werden
// nicht verfolgt; sie ergeben keine Meldung. Feldbezogene Regeln setzen
// persistente Felder (TStringField … als Objekte im Dataset) voraus.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TDfmCircularDataSourceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDfmMasterWithoutFieldsRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDfmRequiredFieldWithoutControlRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDfmControlFieldTypeMismatchRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDfmDuplicateBindingRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForeignFormControlAccessRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDataBindingRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser;

type
  /// <summary>Objekte der Formulardatei und Stelle der Formularklasse in der Unit.</summary>
  TBindingModel = class
  private
    FDocument: TDfmDocument;
    FObjects: TList<TDfmObject>;
    FParents: TDictionary<TDfmObject, TDfmObject>;
    FAnchor: TTextRange;
    FValid: Boolean;
    procedure Collect(AObject, AParent: TDfmObject);
    function FindAnchor(ANode: TSyntaxNode; const AName: string): Boolean;
  public
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    function Value(AObject: TDfmObject; const AName: string): string;
    /// <summary>Objekt dieses Namens in der eigenen Formulardatei; nil sonst (auch bei Modul.Name).</summary>
    function Find(const AName: string): TDfmObject;
    function ParentOf(AObject: TDfmObject): TDfmObject;
    /// <summary>Dataset, an das die Datenquelle AName gebunden ist; nil, wenn nicht auflösbar.</summary>
    function DataSetOf(const ADataSource: string): TDfmObject;
    property Objects: TList<TDfmObject> read FObjects;
    property Valid: Boolean read FValid;
    /// <summary>Name der Formularklasse in der Unit; dort wird gemeldet.</summary>
    property Anchor: TTextRange read FAnchor;
  end;

constructor TBindingModel.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FObjects := TList<TDfmObject>.Create;
  FParents := TDictionary<TDfmObject, TDfmObject>.Create;
  if (AContext.FormText = '') or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  FDocument := TDfmParser.Parse(AContext.FormText);
  if FDocument.Root = nil then
  begin
    Exit;
  end;
  FValid := FindAnchor(AContext.Tree.Root, FDocument.Root.TypeName);
  if FValid then
  begin
    Collect(FDocument.Root, nil);
  end;
end;

destructor TBindingModel.Destroy;
begin
  FParents.Free;
  FObjects.Free;
  FDocument.Free;
  inherited;
end;

// Iterativ (Bericht M1).
function TBindingModel.FindAnchor(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
begin
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      if (Node.Kind = TSyntaxKind.TypeDecl) and SameText(Node.Name, AName) then
      begin
        FAnchor := TTextRange.Create(Node.StartPos.Line, Node.StartPos.Character, Node.StartPos.Line,
          Node.StartPos.Character + Length(AName));
        Exit(True);
      end;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        if Node.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile,
          TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection,
          TSyntaxKind.TypeDecl] then
        begin
          Pending.Push(Node.Children[Index]);
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TBindingModel.Collect(AObject, AParent: TDfmObject);
var
  Child: TDfmObject;
begin
  FObjects.Add(AObject);
  if AParent <> nil then
  begin
    FParents.Add(AObject, AParent);
  end;
  for Child in AObject.Children do
  begin
    Collect(Child, AObject);
  end;
end;

function TBindingModel.Value(AObject: TDfmObject; const AName: string): string;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
  begin
    if SameText(Item.Name, AName) then
    begin
      Exit(Trim(Item.Value));
    end;
  end;
  Result := '';
end;

function TBindingModel.Find(const AName: string): TDfmObject;
var
  Obj: TDfmObject;
begin
  if (AName = '') or (Pos('.', AName) > 0) then
  begin
    Exit(nil);
  end;
  for Obj in FObjects do
  begin
    if SameText(Obj.Name, AName) then
    begin
      Exit(Obj);
    end;
  end;
  Result := nil;
end;

function TBindingModel.ParentOf(AObject: TDfmObject): TDfmObject;
begin
  if not FParents.TryGetValue(AObject, Result) then
  begin
    Result := nil;
  end;
end;

function TBindingModel.DataSetOf(const ADataSource: string): TDfmObject;
var
  Source: TDfmObject;
begin
  Source := Find(ADataSource);
  if Source = nil then
  begin
    Exit(nil);
  end;
  Result := Find(Value(Source, 'DataSet'));
end;

/// <summary>Persistentes Feld: Objekt eines Datasets mit FieldName, Klasse T…Field.</summary>
function IsPersistentField(AModel: TBindingModel; AObject: TDfmObject): Boolean;
begin
  Result := EndsText('Field', AObject.TypeName) and (AModel.Value(AObject, 'FieldName') <> '');
end;

function Unquote(const AValue: string): string;
begin
  Result := AValue;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
  end;
end;

/// <summary>Persistentes Feld AFieldName des Datasets ADataSet; nil ohne.</summary>
function FieldOf(AModel: TBindingModel; ADataSet: TDfmObject; const AFieldName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  for Child in ADataSet.Children do
  begin
    if IsPersistentField(AModel, Child) and SameText(Unquote(AModel.Value(Child, 'FieldName')), AFieldName) then
    begin
      Exit(Child);
    end;
  end;
  Result := nil;
end;

{ TDfmCircularDataSourceRule }

function TDfmCircularDataSourceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-circular-datasource', TRuleSeverity.Warning,
    'Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung');
end;

/// <summary>Dataset, an das AObject über MasterSource bzw. DataSource gebunden ist; nil ohne.</summary>
function LinkedDataSet(AModel: TBindingModel; AObject: TDfmObject): TDfmObject;
begin
  Result := AModel.DataSetOf(AModel.Value(AObject, 'MasterSource'));
  if Result = nil then
  begin
    Result := AModel.DataSetOf(AModel.Value(AObject, 'DataSource'));
  end;
end;

/// <summary>Weg von AStart über die Verknüpfungen zurück zu AStart ("A → B → A"); '' ohne Kreis.</summary>
function CirclePath(AModel: TBindingModel; AStart: TDfmObject): string;
var
  Current: TDfmObject;
  Steps: Integer;
begin
  Current := AStart;
  Result := AStart.Name;
  Steps := 0;
  repeat
    Current := LinkedDataSet(AModel, Current);
    if Current <> nil then
    begin
      Result := Result + ' → ' + Current.Name;
      Inc(Steps);
    end;
  until (Current = nil) or (Current = AStart) or (Steps > AModel.Objects.Count);
  if (Current <> AStart) or (Steps = 0) then
  begin
    Result := '';
  end;
end;

/// <summary>Kante: Dataset → (MasterSource bzw. DataSource) → Datenquelle → DataSet; ein Feld mit DataField
/// ist kein Anfang.</summary>
function StartsLink(AModel: TBindingModel; AObject: TDfmObject): Boolean;
begin
  Result := ((AModel.Value(AObject, 'MasterSource') <> '') or (AModel.Value(AObject, 'DataSource') <> '')) and
    (AModel.Value(AObject, 'DataField') = '');
end;

procedure TDfmCircularDataSourceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  Start, Current: TDfmObject;
  Path: string;
  Reported: TList<TDfmObject>;
begin
  Model := TBindingModel.Create(AContext);
  Reported := TList<TDfmObject>.Create;
  try
    if not Model.Valid then
    begin
      Exit;
    end;
    for Start in Model.Objects do
    begin
      if not StartsLink(Model, Start) or Reported.Contains(Start) then
      begin
        Continue;
      end;
      Path := CirclePath(Model, Start);
      if Path <> '' then
      begin
        // Einmal je Kreis: alle Mitglieder gelten als gemeldet.
        Current := Start;
        repeat
          Reported.Add(Current);
          Current := LinkedDataSet(Model, Current);
        until (Current = nil) or (Current = Start);
        AReport.Add(Model.Anchor, 'Datenquellen bilden einen Kreis: ' + Path);
      end;
    end;
  finally
    Reported.Free;
    Model.Free;
  end;
end;

{ TDfmMasterWithoutFieldsRule }

function TDfmMasterWithoutFieldsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-master-without-fields', TRuleSeverity.Warning,
    'Master-Detail ohne MasterFields');
end;

procedure TDfmMasterWithoutFieldsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  Obj: TDfmObject;
begin
  Model := TBindingModel.Create(AContext);
  try
    if not Model.Valid then
    begin
      Exit;
    end;
    for Obj in Model.Objects do
    begin
      if (Model.Value(Obj, 'MasterSource') <> '') and (Model.Value(Obj, 'MasterFields') = '') then
      begin
        AReport.Add(Model.Anchor, Format('%s hat MasterSource = %s, aber keine MasterFields: das Detail zeigt ' +
          'alle Datensätze', [Obj.Name, Model.Value(Obj, 'MasterSource')]));
      end;
    end;
  finally
    Model.Free;
  end;
end;

{ TDfmRequiredFieldWithoutControlRule }

function TDfmRequiredFieldWithoutControlRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-required-field-without-control', TRuleSeverity.Warning,
    'Pflichtfeld ohne sichtbares Eingabe-Control');
end;

/// <summary>Ist AObject und jeder Vorfahr im Formular sichtbar (kein Visible = False)?</summary>
function IsVisible(AModel: TBindingModel; AObject: TDfmObject): Boolean;
begin
  Result := True;
  while AObject <> nil do
  begin
    if SameText(AModel.Value(AObject, 'Visible'), 'False') then
    begin
      Exit(False);
    end;
    AObject := AModel.ParentOf(AObject);
  end;
end;

/// <summary>Zeigt AControl das Feld AFieldName des Datasets ADataSet? Gitter ohne DataField zeigen alle Felder.
/// </summary>
function ShowsField(AModel: TBindingModel; AControl, ADataSet: TDfmObject; const AFieldName: string): Boolean;
begin
  Result := (AModel.DataSetOf(AModel.Value(AControl, 'DataSource')) = ADataSet) and
    (SameText(Unquote(AModel.Value(AControl, 'DataField')), AFieldName) or
    ContainsText(AControl.TypeName, 'Grid') and (AModel.Value(AControl, 'DataField') = ''));
end;

/// <summary>Meldet das Pflichtfeld AField von ADataSet, wenn kein sichtbares Control es zeigt.</summary>
procedure CheckRequiredField(AModel: TBindingModel; ADataSet, AField: TDfmObject; const AReport: IRuleReport);
var
  Control: TDfmObject;
  FieldName: string;
  Bound, Shown: Boolean;
begin
  FieldName := Unquote(AModel.Value(AField, 'FieldName'));
  Bound := False;
  Shown := False;
  for Control in AModel.Objects do
  begin
    if ShowsField(AModel, Control, ADataSet, FieldName) then
    begin
      Bound := True;
      Shown := Shown or IsVisible(AModel, Control);
    end;
  end;
  if not Shown then
  begin
    AReport.Add(AModel.Anchor, Format('Pflichtfeld %s.%s hat %s', [ADataSet.Name, FieldName,
      IfThen(Bound, 'nur unsichtbare Eingabe-Controls', 'kein Eingabe-Control')]));
  end;
end;

procedure TDfmRequiredFieldWithoutControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  DataSet, Field: TDfmObject;
begin
  Model := TBindingModel.Create(AContext);
  try
    if not Model.Valid then
    begin
      Exit;
    end;
    for DataSet in Model.Objects do
    begin
      for Field in DataSet.Children do
      begin
        if IsPersistentField(Model, Field) and SameText(Model.Value(Field, 'Required'), 'True') then
        begin
          CheckRequiredField(Model, DataSet, Field, AReport);
        end;
      end;
    end;
  finally
    Model.Free;
  end;
end;

{ TDfmControlFieldTypeMismatchRule }

function TDfmControlFieldTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-control-field-type-mismatch', TRuleSeverity.Warning,
    'Datensensitives Control passt nicht zum Feldtyp');
end;

/// <summary>Passt das Control AControlClass zum Feld AFieldClass? True, wenn unbekannt.</summary>
function Compatible(const AControlClass, AFieldClass: string): Boolean;
const
  BlobFields: array[0..3] of string = ('TBlobField', 'TGraphicField', 'TMemoField', 'TWideMemoField');
begin
  if SameText(AControlClass, 'TDBCheckBox') then
  begin
    Exit(SameText(AFieldClass, 'TBooleanField') or not EndsText('Field', AFieldClass) or
      SameText(AFieldClass, 'TStringField') or SameText(AFieldClass, 'TIntegerField') or
      SameText(AFieldClass, 'TSmallintField'));
  end;
  if SameText(AControlClass, 'TDBImage') then
  begin
    Exit(SameText(AFieldClass, 'TGraphicField') or SameText(AFieldClass, 'TBlobField'));
  end;
  if SameText(AControlClass, 'TDBEdit') or SameText(AControlClass, 'TDBText') then
  begin
    Exit(not SameText(AFieldClass, 'TBooleanField') and not MatchText(AFieldClass, BlobFields));
  end;
  Result := True;
end;

procedure TDfmControlFieldTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  Control, DataSet, Field: TDfmObject;
  FieldName: string;
begin
  Model := TBindingModel.Create(AContext);
  try
    if not Model.Valid then
    begin
      Exit;
    end;
    for Control in Model.Objects do
    begin
      FieldName := Unquote(Model.Value(Control, 'DataField'));
      if FieldName = '' then
      begin
        Continue;
      end;
      DataSet := Model.DataSetOf(Model.Value(Control, 'DataSource'));
      if DataSet = nil then
      begin
        Continue;
      end;
      Field := FieldOf(Model, DataSet, FieldName);
      if (Field <> nil) and not Compatible(Control.TypeName, Field.TypeName) then
      begin
        AReport.Add(Model.Anchor, Format('%s: %s zeigt das Feld %s vom Typ %s', [Control.Name, Control.TypeName,
          FieldName, Field.TypeName]));
      end;
    end;
  finally
    Model.Free;
  end;
end;

{ TDfmDuplicateBindingRule }

function TDfmDuplicateBindingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-duplicate-binding', TRuleSeverity.Warning,
    'Zwei Controls an demselben DataSource und DataField');
end;

procedure TDfmDuplicateBindingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  Control: TDfmObject;
  Key: string;
  Seen: TDictionary<string, TDfmObject>;
  First: TDfmObject;
begin
  Model := TBindingModel.Create(AContext);
  Seen := TDictionary<string, TDfmObject>.Create;
  try
    if not Model.Valid then
    begin
      Exit;
    end;
    for Control in Model.Objects do
    begin
      if (Model.Value(Control, 'DataSource') = '') or (Model.Value(Control, 'DataField') = '') then
      begin
        Continue;
      end;
      // Anzeige-Controls dürfen dasselbe Feld zusätzlich zeigen.
      if SameText(Control.TypeName, 'TDBText') or SameText(Control.TypeName, 'TDBImage') then
      begin
        Continue;
      end;
      Key := LowerCase(Model.Value(Control, 'DataSource') + '|' + Unquote(Model.Value(Control, 'DataField')));
      if Seen.TryGetValue(Key, First) then
      begin
        AReport.Add(Model.Anchor, Format('%s und %s sind beide an %s.%s gebunden', [First.Name, Control.Name,
          Model.Value(Control, 'DataSource'), Unquote(Model.Value(Control, 'DataField'))]));
      end
      else
      begin
        Seen.Add(Key, Control);
      end;
    end;
  finally
    Seen.Free;
    Model.Free;
  end;
end;

{ TForeignFormControlAccessRule }

function TForeignFormControlAccessRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('foreign-form-control-access', TRuleSeverity.Warning,
    'Zugriff auf Controls eines anderen Formulars');
end;

const
  FormBases: array[0..3] of string = ('TForm', 'TCustomForm', 'TFrame', 'TCustomFrame');

/// <summary>Erreicht die Vorfahrenkette von AClassName im Index eine Formularklasse?</summary>
function IsFormClass(const AIndex: ISymbolIndex; const AClassName: string): Boolean;
var
  Name: string;
  Location: TSymbolLocation;
  Found: Boolean;
  Depth: Integer;
begin
  Name := AClassName;
  for Depth := 0 to 16 do
  begin
    if MatchText(Name, FormBases) then
    begin
      Exit(Depth > 0);
    end;
    Found := False;
    for Location in AIndex.FindSymbols(Name) do
    begin
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
        (Length(Location.Symbol.Ancestors) > 0) then
      begin
        Name := Location.Symbol.Ancestors[0];
        Found := True;
        Break;
      end;
    end;
    if not Found then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Token ohne Kommentare und Direktiven.</summary>
function CodeTokens(const ATokens: TArray<TPascalToken>): TArray<TPascalToken>;
var
  Token: TPascalToken;
begin
  Result := nil;
  for Token in ATokens do
  begin
    if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + [Token];
    end;
  end;
end;

/// <summary>Steht ab AIndex Name.Feld. am Anfang eines Ausdrucks (nicht hinter einem Punkt)?</summary>
function IsQualifiedAccess(const ACode: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (ACode[AIndex].Kind = TPascalTokenKind.Identifier) and ACode[AIndex + 1].IsSymbol('.') and
    (ACode[AIndex + 2].Kind = TPascalTokenKind.Identifier) and ACode[AIndex + 3].IsSymbol('.');
  Result := Result and ((AIndex = 0) or not ACode[AIndex - 1].IsSymbol('.'));
end;

/// <summary>Formularklasse der globalen Variablen AName aus einer anderen Unit; '' ohne.</summary>
function ForeignFormClass(const AContext: TRuleContext; const AName: string): string;
var
  Location: TSymbolLocation;
begin
  Result := '';
  for Location in AContext.Index.FindSymbols(AName) do
  begin
    if (Location.Symbol.Kind = TIndexSymbolKind.Variable) and (Location.Symbol.Container = '') and
      not SameText(Location.UnitName, AContext.UnitName) then
    begin
      Result := Location.Symbol.TypeName;
      Break;
    end;
  end;
  if (Result <> '') and not IsFormClass(AContext.Index, Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Ist AName ein Feld der Klasse AFormClass?</summary>
function IsFormField(const AContext: TRuleContext; const AName, AFormClass: string): Boolean;
var
  Member: TSymbolLocation;
begin
  Result := False;
  for Member in AContext.Index.FindSymbols(AName) do
  begin
    Result := Result or (Member.Symbol.Kind = TIndexSymbolKind.Field) and
      SameText(Member.Symbol.Container, AFormClass);
  end;
end;

procedure TForeignFormControlAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Code: TArray<TPascalToken>;
  Index: Integer;
  FormClass: string;
begin
  if (AContext.Index = nil) or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  Code := CodeTokens(AContext.Tree.Tokens);
  for Index := 0 to High(Code) - 3 do
  begin
    // Form2.Edit1.…: globale Formularvariable, Punkt, Feld, Punkt.
    if not IsQualifiedAccess(Code, Index) then
    begin
      Continue;
    end;
    FormClass := ForeignFormClass(AContext, Code[Index].Text);
    if (FormClass <> '') and IsFormField(AContext, Code[Index + 2].Text, FormClass) then
    begin
      AReport.Add(TTextRange.Create(Code[Index].StartPos, Code[Index + 2].EndPos),
        Format('Zugriff auf %s.%s eines anderen Formulars; besser über eine Methode oder Property von %s',
        [Code[Index].Text, Code[Index + 2].Text, FormClass]), TRuleConfidence.Medium);
    end;
  end;
end;

procedure RegisterDataBindingRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDfmCircularDataSourceRule.Create);
  ARegistry.Register(TDfmMasterWithoutFieldsRule.Create);
  ARegistry.Register(TDfmRequiredFieldWithoutControlRule.Create);
  ARegistry.Register(TDfmControlFieldTypeMismatchRule.Create);
  ARegistry.Register(TDfmDuplicateBindingRule.Create);
  ARegistry.Register(TForeignFormControlAccessRule.Create);
end;

end.
