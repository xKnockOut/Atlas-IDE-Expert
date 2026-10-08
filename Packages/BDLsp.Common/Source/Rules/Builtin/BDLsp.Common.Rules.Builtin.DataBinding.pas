unit BDLsp.Common.Rules.Builtin.DataBinding;

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
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Registry;

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
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Pascal.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Dfm.Contract,
  BDLsp.Common.Dfm.Parser;

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
    Exit;
  FDocument := TDfmParser.Parse(AContext.FormText);
  if FDocument.Root = nil then
    Exit;
  FValid := FindAnchor(AContext.Tree.Root, FDocument.Root.TypeName);
  if FValid then
    Collect(FDocument.Root, nil);
end;

destructor TBindingModel.Destroy;
begin
  FParents.Free;
  FObjects.Free;
  FDocument.Free;
  inherited;
end;

function TBindingModel.FindAnchor(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.TypeDecl) and SameText(ANode.Name, AName) then
  begin
    FAnchor := TTextRange.Create(ANode.StartPos.Line, ANode.StartPos.Character, ANode.StartPos.Line,
      ANode.StartPos.Character + Length(AName));
    Exit(True);
  end;
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode.Children[Index].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile, TSyntaxKind.InterfaceSection,
      TSyntaxKind.ImplementationSection, TSyntaxKind.TypeSection, TSyntaxKind.TypeDecl] then
      if FindAnchor(ANode.Children[Index], AName) then
        Exit(True);
  Result := False;
end;

procedure TBindingModel.Collect(AObject, AParent: TDfmObject);
var
  Child: TDfmObject;
begin
  FObjects.Add(AObject);
  if AParent <> nil then
    FParents.Add(AObject, AParent);
  for Child in AObject.Children do
    Collect(Child, AObject);
end;

function TBindingModel.Value(AObject: TDfmObject; const AName: string): string;
var
  Item: TDfmProperty;
begin
  for Item in AObject.Properties do
    if SameText(Item.Name, AName) then
      Exit(Trim(Item.Value));
  Result := '';
end;

function TBindingModel.Find(const AName: string): TDfmObject;
var
  Obj: TDfmObject;
begin
  if (AName = '') or (Pos('.', AName) > 0) then
    Exit(nil);
  for Obj in FObjects do
    if SameText(Obj.Name, AName) then
      Exit(Obj);
  Result := nil;
end;

function TBindingModel.ParentOf(AObject: TDfmObject): TDfmObject;
begin
  if not FParents.TryGetValue(AObject, Result) then
    Result := nil;
end;

function TBindingModel.DataSetOf(const ADataSource: string): TDfmObject;
var
  Source: TDfmObject;
begin
  Source := Find(ADataSource);
  if Source = nil then
    Exit(nil);
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
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
end;

/// <summary>Persistentes Feld AFieldName des Datasets ADataSet; nil ohne.</summary>
function FieldOf(AModel: TBindingModel; ADataSet: TDfmObject; const AFieldName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  for Child in ADataSet.Children do
    if IsPersistentField(AModel, Child) and SameText(Unquote(AModel.Value(Child, 'FieldName')), AFieldName) then
      Exit(Child);
  Result := nil;
end;

{ TDfmCircularDataSourceRule }

function TDfmCircularDataSourceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-circular-datasource', TRuleSeverity.Warning,
    'Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung');
end;

procedure TDfmCircularDataSourceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  Start, Current, Next: TDfmObject;
  Path: string;
  Steps: Integer;
  Reported: TList<TDfmObject>;
begin
  Model := TBindingModel.Create(AContext);
  Reported := TList<TDfmObject>.Create;
  try
    if not Model.Valid then
      Exit;
    for Start in Model.Objects do
    begin
      // Kante: Dataset → (MasterSource bzw. DataSource) → Datenquelle → DataSet.
      if (Model.Value(Start, 'MasterSource') = '') and (Model.Value(Start, 'DataSource') = '') then
        Continue;
      if Model.Value(Start, 'DataField') <> '' then
        Continue;
      Current := Start;
      Path := Start.Name;
      Steps := 0;
      repeat
        Next := Model.DataSetOf(Model.Value(Current, 'MasterSource'));
        if Next = nil then
          Next := Model.DataSetOf(Model.Value(Current, 'DataSource'));
        if Next = nil then
          Break;
        Path := Path + ' → ' + Next.Name;
        Current := Next;
        Inc(Steps);
      until (Current = Start) or (Steps > Model.Objects.Count);
      if (Current = Start) and (Steps > 0) and not Reported.Contains(Start) then
      begin
        // Einmal je Kreis: alle Mitglieder gelten als gemeldet.
        Current := Start;
        repeat
          Reported.Add(Current);
          Next := Model.DataSetOf(Model.Value(Current, 'MasterSource'));
          if Next = nil then
            Next := Model.DataSetOf(Model.Value(Current, 'DataSource'));
          Current := Next;
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
      Exit;
    for Obj in Model.Objects do
      if (Model.Value(Obj, 'MasterSource') <> '') and (Model.Value(Obj, 'MasterFields') = '') then
        AReport.Add(Model.Anchor, Format('%s hat MasterSource = %s, aber keine MasterFields: das Detail zeigt ' +
          'alle Datensätze', [Obj.Name, Model.Value(Obj, 'MasterSource')]));
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
      Exit(False);
    AObject := AModel.ParentOf(AObject);
  end;
end;

procedure TDfmRequiredFieldWithoutControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Model: TBindingModel;
  DataSet, Field, Control: TDfmObject;
  FieldName: string;
  Bound, Shown: Boolean;
begin
  Model := TBindingModel.Create(AContext);
  try
    if not Model.Valid then
      Exit;
    for DataSet in Model.Objects do
      for Field in DataSet.Children do
      begin
        if not IsPersistentField(Model, Field) or not SameText(Model.Value(Field, 'Required'), 'True') then
          Continue;
        FieldName := Unquote(Model.Value(Field, 'FieldName'));
        Bound := False;
        Shown := False;
        for Control in Model.Objects do
        begin
          if Model.DataSetOf(Model.Value(Control, 'DataSource')) <> DataSet then
            Continue;
          // Gitter ohne DataField zeigen alle Felder.
          if SameText(Unquote(Model.Value(Control, 'DataField')), FieldName) or
            (ContainsText(Control.TypeName, 'Grid') and (Model.Value(Control, 'DataField') = '')) then
          begin
            Bound := True;
            if IsVisible(Model, Control) then
              Shown := True;
          end;
        end;
        if not Shown then
          AReport.Add(Model.Anchor, Format('Pflichtfeld %s.%s hat %s', [DataSet.Name, FieldName,
            IfThen(Bound, 'nur unsichtbare Eingabe-Controls', 'kein Eingabe-Control')]));
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
    Exit(SameText(AFieldClass, 'TBooleanField') or not EndsText('Field', AFieldClass) or
      SameText(AFieldClass, 'TStringField') or SameText(AFieldClass, 'TIntegerField') or
      SameText(AFieldClass, 'TSmallintField'));
  if SameText(AControlClass, 'TDBImage') then
    Exit(SameText(AFieldClass, 'TGraphicField') or SameText(AFieldClass, 'TBlobField'));
  if SameText(AControlClass, 'TDBEdit') or SameText(AControlClass, 'TDBText') then
    Exit(not SameText(AFieldClass, 'TBooleanField') and not MatchText(AFieldClass, BlobFields));
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
      Exit;
    for Control in Model.Objects do
    begin
      FieldName := Unquote(Model.Value(Control, 'DataField'));
      if FieldName = '' then
        Continue;
      DataSet := Model.DataSetOf(Model.Value(Control, 'DataSource'));
      if DataSet = nil then
        Continue;
      Field := FieldOf(Model, DataSet, FieldName);
      if (Field <> nil) and not Compatible(Control.TypeName, Field.TypeName) then
        AReport.Add(Model.Anchor, Format('%s: %s zeigt das Feld %s vom Typ %s', [Control.Name, Control.TypeName,
          FieldName, Field.TypeName]));
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
      Exit;
    for Control in Model.Objects do
    begin
      if (Model.Value(Control, 'DataSource') = '') or (Model.Value(Control, 'DataField') = '') then
        Continue;
      // Anzeige-Controls dürfen dasselbe Feld zusätzlich zeigen.
      if SameText(Control.TypeName, 'TDBText') or SameText(Control.TypeName, 'TDBImage') then
        Continue;
      Key := LowerCase(Model.Value(Control, 'DataSource') + '|' + Unquote(Model.Value(Control, 'DataField')));
      if Seen.TryGetValue(Key, First) then
        AReport.Add(Model.Anchor, Format('%s und %s sind beide an %s.%s gebunden', [First.Name, Control.Name,
          Model.Value(Control, 'DataSource'), Unquote(Model.Value(Control, 'DataField'))]))
      else
        Seen.Add(Key, Control);
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
      Exit(Depth > 0);
    Found := False;
    for Location in AIndex.FindSymbols(Name) do
      if (Location.Symbol.Kind = TIndexSymbolKind.ClassType) and (Location.Symbol.Container = '') and
        (Length(Location.Symbol.Ancestors) > 0) then
      begin
        Name := Location.Symbol.Ancestors[0];
        Found := True;
        Break;
      end;
    if not Found then
      Exit(False);
  end;
  Result := False;
end;

procedure TForeignFormControlAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<TPascalToken>;
  Token: TPascalToken;
  Index: Integer;
  Location, Member: TSymbolLocation;
  FormClass: string;
  IsField: Boolean;
begin
  if (AContext.Index = nil) or (AContext.Tree = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Token in Tokens do
    if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Token];
  for Index := 0 to High(Code) - 3 do
  begin
    // Form2.Edit1.…: globale Formularvariable, Punkt, Feld, Punkt.
    if (Code[Index].Kind <> TPascalTokenKind.Identifier) or not Code[Index + 1].IsSymbol('.') or
      (Code[Index + 2].Kind <> TPascalTokenKind.Identifier) or not Code[Index + 3].IsSymbol('.') then
      Continue;
    if (Index > 0) and Code[Index - 1].IsSymbol('.') then
      Continue;
    FormClass := '';
    for Location in AContext.Index.FindSymbols(Code[Index].Text) do
      if (Location.Symbol.Kind = TIndexSymbolKind.Variable) and (Location.Symbol.Container = '') and
        not SameText(Location.UnitName, AContext.UnitName) then
      begin
        FormClass := Location.Symbol.TypeName;
        Break;
      end;
    if (FormClass = '') or not IsFormClass(AContext.Index, FormClass) then
      Continue;
    IsField := False;
    for Member in AContext.Index.FindSymbols(Code[Index + 2].Text) do
      if (Member.Symbol.Kind = TIndexSymbolKind.Field) and SameText(Member.Symbol.Container, FormClass) then
        IsField := True;
    if IsField then
      AReport.Add(TTextRange.Create(Code[Index].StartPos, Code[Index + 2].EndPos),
        Format('Zugriff auf %s.%s eines anderen Formulars; besser über eine Methode oder Property von %s',
        [Code[Index].Text, Code[Index + 2].Text, FormClass]), TRuleConfidence.Medium);
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
