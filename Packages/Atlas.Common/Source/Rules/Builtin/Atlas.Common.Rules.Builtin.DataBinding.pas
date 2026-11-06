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
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDataBindingText = (CycleTitle, Cycle, MasterTitle, NoMasterFields, RequiredTitle, RequiredField, OnlyInvisible,
    NoControl, TypeTitle, ShowsField, DoubleTitle, BothBound, ForeignTitle, ForeignAccess);

const
  cTexts: array[TDataBindingText] of TAtlasText = (
    (De: 'Zirkuläre Master-Detail- bzw. DataSource-Verknüpfung'; En: 'Circular master-detail or DataSource link'),
    (De: 'Datenquellen bilden einen Kreis: '; En: 'Data sources form a cycle: '),
    (De: 'Master-Detail ohne MasterFields'; En: 'Master-detail without MasterFields'),
    (De: '%s hat MasterSource = %s, aber keine MasterFields: das Detail zeigt alle Datensätze';
     En: '%s has MasterSource = %s but no MasterFields: the detail shows all records'),
    (De: 'Pflichtfeld ohne sichtbares Eingabe-Control'; En: 'Required field without a visible input control'),
    (De: 'Pflichtfeld %s.%s hat %s'; En: 'Required field %s.%s has %s'),
    (De: 'nur unsichtbare Eingabe-Controls'; En: 'only invisible input controls'),
    (De: 'kein Eingabe-Control'; En: 'no input control'),
    (De: 'Datensensitives Control passt nicht zum Feldtyp'; En: 'Data-aware control does not fit the field type'),
    (De: '%s: %s zeigt das Feld %s vom Typ %s'; En: '%s: %s shows the field %s of type %s'),
    (De: 'Zwei Controls an demselben DataSource und DataField';
     En: 'Two controls on the same DataSource and DataField'),
    (De: '%s und %s sind beide an %s.%s gebunden'; En: '%s and %s are both bound to %s.%s'),
    (De: 'Zugriff auf Controls eines anderen Formulars'; En: 'Access to controls of another form'),
    (De: 'Zugriff auf %s.%s eines anderen Formulars; besser über eine Methode oder Property von %s';
     En: 'Access to %s.%s of another form; better via a method or property of %s'));

{$SCOPEDENUMS OFF}

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
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.TypeDecl) and SameText(mNode.Name, AName) then
      begin
        FAnchor := TTextRange.Create(mNode.StartPos.Line, mNode.StartPos.Character, mNode.StartPos.Line,
          mNode.StartPos.Character + Length(AName));
        Exit(True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        if mNode.Children[mIndex].Kind in [TSyntaxKind.UnitFile, TSyntaxKind.ProgramFile,
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

procedure TBindingModel.Collect(AObject, AParent: TDfmObject);
var
  mChild: TDfmObject;
begin
  FObjects.Add(AObject);
  if AParent <> nil then
  begin
    FParents.Add(AObject, AParent);
  end;
  for mChild in AObject.Children do
  begin
    Collect(mChild, AObject);
  end;
end;

function TBindingModel.Value(AObject: TDfmObject; const AName: string): string;
var
  mItem: TDfmProperty;
begin
  for mItem in AObject.Properties do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit(Trim(mItem.Value));
    end;
  end;
  Result := '';
end;

function TBindingModel.Find(const AName: string): TDfmObject;
var
  mObj: TDfmObject;
begin
  if (AName = '') or (Pos('.', AName) > 0) then
  begin
    Exit(nil);
  end;
  for mObj in FObjects do
  begin
    if SameText(mObj.Name, AName) then
    begin
      Exit(mObj);
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
  mSource: TDfmObject;
begin
  mSource := Find(ADataSource);
  if mSource = nil then
  begin
    Exit(nil);
  end;
  Result := Find(Value(mSource, 'DataSet'));
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
  mChild: TDfmObject;
begin
  for mChild in ADataSet.Children do
  begin
    if IsPersistentField(AModel, mChild) and SameText(Unquote(AModel.Value(mChild, 'FieldName')), AFieldName) then
    begin
      Exit(mChild);
    end;
  end;
  Result := nil;
end;

{ TDfmCircularDataSourceRule }

function TDfmCircularDataSourceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-circular-datasource', TRuleSeverity.Warning,
    cTexts[TDataBindingText.CycleTitle].Text);
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
  mCurrent: TDfmObject;
  mSteps: Integer;
begin
  mCurrent := AStart;
  Result := AStart.Name;
  mSteps := 0;
  repeat
    mCurrent := LinkedDataSet(AModel, mCurrent);
    if mCurrent <> nil then
    begin
      Result := Result + ' → ' + mCurrent.Name;
      Inc(mSteps);
    end;
  until (mCurrent = nil) or (mCurrent = AStart) or (mSteps > AModel.Objects.Count);
  if (mCurrent <> AStart) or (mSteps = 0) then
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
  mModel: TBindingModel;
  mStart, mCurrent: TDfmObject;
  mPath: string;
  mReported: TList<TDfmObject>;
begin
  mModel := TBindingModel.Create(AContext);
  mReported := TList<TDfmObject>.Create;
  try
    if not mModel.Valid then
    begin
      Exit;
    end;
    for mStart in mModel.Objects do
    begin
      if not StartsLink(mModel, mStart) or mReported.Contains(mStart) then
      begin
        Continue;
      end;
      mPath := CirclePath(mModel, mStart);
      if mPath <> '' then
      begin
        // Einmal je Kreis: alle Mitglieder gelten als gemeldet.
        mCurrent := mStart;
        repeat
          mReported.Add(mCurrent);
          mCurrent := LinkedDataSet(mModel, mCurrent);
        until (mCurrent = nil) or (mCurrent = mStart);
        AReport.Add(mModel.Anchor, cTexts[TDataBindingText.Cycle].Text + mPath);
      end;
    end;
  finally
    mReported.Free;
    mModel.Free;
  end;
end;

{ TDfmMasterWithoutFieldsRule }

function TDfmMasterWithoutFieldsRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-master-without-fields', TRuleSeverity.Warning,
    cTexts[TDataBindingText.MasterTitle].Text);
end;

procedure TDfmMasterWithoutFieldsRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TBindingModel;
  mObj: TDfmObject;
begin
  mModel := TBindingModel.Create(AContext);
  try
    if not mModel.Valid then
    begin
      Exit;
    end;
    for mObj in mModel.Objects do
    begin
      if (mModel.Value(mObj, 'MasterSource') <> '') and (mModel.Value(mObj, 'MasterFields') = '') then
      begin
        AReport.Add(mModel.Anchor, cTexts[TDataBindingText.NoMasterFields].Fmt([mObj.Name, mModel.Value(mObj,
          'MasterSource')]));
      end;
    end;
  finally
    mModel.Free;
  end;
end;

{ TDfmRequiredFieldWithoutControlRule }

function TDfmRequiredFieldWithoutControlRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-required-field-without-control', TRuleSeverity.Warning,
    cTexts[TDataBindingText.RequiredTitle].Text);
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
  mControl: TDfmObject;
  mFieldName: string;
  mBound, mShown: Boolean;
begin
  mFieldName := Unquote(AModel.Value(AField, 'FieldName'));
  mBound := False;
  mShown := False;
  for mControl in AModel.Objects do
  begin
    if ShowsField(AModel, mControl, ADataSet, mFieldName) then
    begin
      mBound := True;
      mShown := mShown or IsVisible(AModel, mControl);
    end;
  end;
  if not mShown then
  begin
    AReport.Add(AModel.Anchor, cTexts[TDataBindingText.RequiredField].Fmt([ADataSet.Name, mFieldName,
      IfThen(mBound, cTexts[TDataBindingText.OnlyInvisible].Text, cTexts[TDataBindingText.NoControl].Text)]));
  end;
end;

procedure TDfmRequiredFieldWithoutControlRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TBindingModel;
  mDataSet, mField: TDfmObject;
begin
  mModel := TBindingModel.Create(AContext);
  try
    if not mModel.Valid then
    begin
      Exit;
    end;
    for mDataSet in mModel.Objects do
    begin
      for mField in mDataSet.Children do
      begin
        if IsPersistentField(mModel, mField) and SameText(mModel.Value(mField, 'Required'), 'True') then
        begin
          CheckRequiredField(mModel, mDataSet, mField, AReport);
        end;
      end;
    end;
  finally
    mModel.Free;
  end;
end;

{ TDfmControlFieldTypeMismatchRule }

function TDfmControlFieldTypeMismatchRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-control-field-type-mismatch', TRuleSeverity.Warning,
    cTexts[TDataBindingText.TypeTitle].Text);
end;

/// <summary>Passt das Control AControlClass zum Feld AFieldClass? True, wenn unbekannt.</summary>
function Compatible(const AControlClass, AFieldClass: string): Boolean;
const
  cBlobFields: array[0..3] of string = ('TBlobField', 'TGraphicField', 'TMemoField', 'TWideMemoField');
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
    Exit(not SameText(AFieldClass, 'TBooleanField') and not MatchText(AFieldClass, cBlobFields));
  end;
  Result := True;
end;

procedure TDfmControlFieldTypeMismatchRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TBindingModel;
  mControl, mDataSet, mField: TDfmObject;
  mFieldName: string;
begin
  mModel := TBindingModel.Create(AContext);
  try
    if not mModel.Valid then
    begin
      Exit;
    end;
    for mControl in mModel.Objects do
    begin
      mFieldName := Unquote(mModel.Value(mControl, 'DataField'));
      if mFieldName = '' then
      begin
        Continue;
      end;
      mDataSet := mModel.DataSetOf(mModel.Value(mControl, 'DataSource'));
      if mDataSet = nil then
      begin
        Continue;
      end;
      mField := FieldOf(mModel, mDataSet, mFieldName);
      if (mField <> nil) and not Compatible(mControl.TypeName, mField.TypeName) then
      begin
        AReport.Add(mModel.Anchor, cTexts[TDataBindingText.ShowsField].Fmt([mControl.Name, mControl.TypeName,
          mFieldName, mField.TypeName]));
      end;
    end;
  finally
    mModel.Free;
  end;
end;

{ TDfmDuplicateBindingRule }

function TDfmDuplicateBindingRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('dfm-duplicate-binding', TRuleSeverity.Warning,
    cTexts[TDataBindingText.DoubleTitle].Text);
end;

procedure TDfmDuplicateBindingRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mModel: TBindingModel;
  mControl: TDfmObject;
  mKey: string;
  mSeen: TDictionary<string, TDfmObject>;
  mFirst: TDfmObject;
begin
  mModel := TBindingModel.Create(AContext);
  mSeen := TDictionary<string, TDfmObject>.Create;
  try
    if not mModel.Valid then
    begin
      Exit;
    end;
    for mControl in mModel.Objects do
    begin
      if (mModel.Value(mControl, 'DataSource') = '') or (mModel.Value(mControl, 'DataField') = '') then
      begin
        Continue;
      end;
      // Anzeige-Controls dürfen dasselbe Feld zusätzlich zeigen.
      if SameText(mControl.TypeName, 'TDBText') or SameText(mControl.TypeName, 'TDBImage') then
      begin
        Continue;
      end;
      mKey := LowerCase(mModel.Value(mControl, 'DataSource') + '|' + Unquote(mModel.Value(mControl, 'DataField')));
      if mSeen.TryGetValue(mKey, mFirst) then
      begin
        AReport.Add(mModel.Anchor, cTexts[TDataBindingText.BothBound].Fmt([mFirst.Name, mControl.Name,
          mModel.Value(mControl, 'DataSource'), Unquote(mModel.Value(mControl, 'DataField'))]));
      end
      else
      begin
        mSeen.Add(mKey, mControl);
      end;
    end;
  finally
    mSeen.Free;
    mModel.Free;
  end;
end;

{ TForeignFormControlAccessRule }

function TForeignFormControlAccessRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('foreign-form-control-access', TRuleSeverity.Warning,
    cTexts[TDataBindingText.ForeignTitle].Text);
end;

const
  cFormBases: array[0..3] of string = ('TForm', 'TCustomForm', 'TFrame', 'TCustomFrame');

/// <summary>Erreicht die Vorfahrenkette von AClassName im Index eine Formularklasse?</summary>
function IsFormClass(const AIndex: ISymbolIndex; const AClassName: string): Boolean;
var
  mName: string;
  mLocation: TSymbolLocation;
  mFound: Boolean;
  mDepth: Integer;
begin
  mName := AClassName;
  for mDepth := 0 to 16 do
  begin
    if MatchText(mName, cFormBases) then
    begin
      Exit(mDepth > 0);
    end;
    mFound := False;
    for mLocation in AIndex.FindSymbols(mName) do
    begin
      if (mLocation.Symbol.Kind = TIndexSymbolKind.ClassType) and (mLocation.Symbol.Container = '') and
        (Length(mLocation.Symbol.Ancestors) > 0) then
      begin
        mName := mLocation.Symbol.Ancestors[0];
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Token ohne Kommentare und Direktiven.</summary>
function CodeTokens(const ATokens: TArray<TPascalToken>): TArray<TPascalToken>;
var
  mToken: TPascalToken;
begin
  Result := nil;
  for mToken in ATokens do
  begin
    if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Result := Result + [mToken];
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
  mLocation: TSymbolLocation;
begin
  Result := '';
  for mLocation in AContext.Index.FindSymbols(AName) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Variable) and (mLocation.Symbol.Container = '') and
      not SameText(mLocation.UnitName, AContext.UnitName) then
    begin
      Result := mLocation.Symbol.TypeName;
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
  mMember: TSymbolLocation;
begin
  Result := False;
  for mMember in AContext.Index.FindSymbols(AName) do
  begin
    Result := Result or (mMember.Symbol.Kind = TIndexSymbolKind.Field) and
      SameText(mMember.Symbol.Container, AFormClass);
  end;
end;

procedure TForeignFormControlAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCode: TArray<TPascalToken>;
  mIndex: Integer;
  mFormClass: string;
begin
  if (AContext.Index = nil) or (AContext.Tree = nil) then
  begin
    Exit;
  end;
  mCode := CodeTokens(AContext.Tree.Tokens);
  for mIndex := 0 to High(mCode) - 3 do
  begin
    // Form2.Edit1.…: globale Formularvariable, Punkt, Feld, Punkt.
    if not IsQualifiedAccess(mCode, mIndex) then
    begin
      Continue;
    end;
    mFormClass := ForeignFormClass(AContext, mCode[mIndex].Text);
    if (mFormClass <> '') and IsFormField(AContext, mCode[mIndex + 2].Text, mFormClass) then
    begin
      AReport.Add(TTextRange.Create(mCode[mIndex].StartPos, mCode[mIndex + 2].EndPos),
        cTexts[TDataBindingText.ForeignAccess].Fmt(
        [mCode[mIndex].Text, mCode[mIndex + 2].Text, mFormClass]), TRuleConfidence.Medium);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DataBinding', cTexts);

end.
