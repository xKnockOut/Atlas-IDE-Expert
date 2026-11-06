unit Atlas.Common.Dfm.FormModel;

// Formularmodell (#267): verknüpft eine Formulardatei (.dfm/.fmx) mit ihrer
// Unit. Liefert
// - den Objektbaum aus TDfmParser samt Klassen der Objekte,
// - je Objekt das published-Feld der Formularklasse,
// - je Ereignis (OnClick = Button1Click) die Methode,
// - geerbte Formulare (inherited) mit dem Vorfahren aus der Unit,
// - Verweise auf andere Module (DataSource = DM.dsKunden).
// Binäre Formulardateien (Kennung TPF0) werden gemeldet (Binary) und über die
// Umwandlung in Text (#122) trotzdem gelesen.
//
// Alle Stellen, die DFM und Code verbinden (Referenzsuche, Umbenennen,
// Vervollständigung, Hover), lesen die Formulardatei über dieses Modell.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Dfm.Contract;

type
  TIndexSymbolKinds = set of TIndexSymbolKind;

  /// <summary>Objekt der Formulardatei mit dem passenden Feld der Formularklasse.</summary>
  TFormComponent = record
    Obj: TDfmObject;
    /// <summary>True bei "inherited Name: TKlasse" (Objekt stammt aus dem Vorfahrenformular).</summary>
    IsInherited: Boolean;
    HasField: Boolean;
    Field: TIndexSymbol;
  end;

  /// <summary>Ereignis-Eigenschaft mit der zugeordneten Methode.</summary>
  TFormEvent = record
    Obj: TDfmObject;
    Event: TDfmProperty;
    HasMethod: Boolean;
    /// <summary>Deklaration der Methode in der Formularklasse.</summary>
    Method: TIndexSymbol;
  end;

  /// <summary>Verweis auf eine Komponente eines anderen Moduls, z. B. DataSource = DM.dsKunden.</summary>
  TFormModuleReference = record
    Obj: TDfmObject;
    Reference: TDfmProperty;
    ModuleName: string;
    ComponentName: string;
  end;

  TFormModel = class
  private
    FDocument: TDfmDocument;
    FBinary: Boolean;
    FUnit: TUnitIndex;
    FHasUnit: Boolean;
    FAncestor: string;
    FComponents: TArray<TFormComponent>;
    FEvents: TArray<TFormEvent>;
    FReferences: TArray<TFormModuleReference>;
    procedure Collect(AObject: TDfmObject);
    function FindMember(const AName: string; AKinds: TIndexSymbolKinds; out ASymbol: TIndexSymbol): Boolean;
    function GetFormClass: string;
  public
    /// <summary>Liest die Formulardatei und, falls AUnitText nicht leer ist, die Unit dazu.</summary>
    constructor Create(const AFormText, AUnitText, AUnitFile: string); overload;
    /// <summary>Wie oben mit AUnitFile = ''.</summary>
    constructor Create(const AFormText, AUnitText: string); overload;
    /// <summary>Wie oben ohne Unit (AUnitText = '', AUnitFile = '').</summary>
    constructor Create(const AFormText: string); overload;
    destructor Destroy; override;
    /// <summary>Binäre Formulardatei (beginnt mit TPF0)?</summary>
    class function IsBinary(const AText: string): Boolean; static;
    /// <summary>Stellen, an denen AName als Komponentenname oder Ereignis-Handler vorkommt.</summary>
    function Occurrences(const AName: string): TArray<TTextRange>;
    /// <summary>Formularobjekt mit diesem Namen; nil ohne.</summary>
    function FindComponent(const AName: string): TDfmObject;
    /// <summary>Nennt AName das Formular selbst oder eine eigene Komponente (auch einen eingebetteten Rahmen wie
    /// Frame11 in Frame11.Button1)? Dann ist ein Verweis AName.X kein Verweis auf ein anderes Modul.</summary>
    function IsOwnName(const AName: string): Boolean;
    /// <summary>Andere Module, auf die References verweisen (DM in DataSource = DM.dsKunden), ohne das eigene
    /// Formular und eigene Komponenten, jedes einmal.</summary>
    function ForeignModules: TArray<string>;
    /// <summary>ForeignModules der Formulardatei AFormText; leer ohne Text.</summary>
    class function ForeignModulesOf(const AFormText: string): TArray<string>; static;
    /// <summary>Binär gespeichert; gelesen wird die Umwandlung in Text.</summary>
    property Binary: Boolean read FBinary;
    property Document: TDfmDocument read FDocument;
    /// <summary>Klasse des Formulars, z. B. TForm1; '' ohne Wurzelobjekt.</summary>
    property FormClass: string read GetFormClass;
    /// <summary>Vorfahr der Formularklasse laut Unit (z. B. TBasisForm bei geerbten Formularen); '' ohne
    /// Unit.</summary>
    property Ancestor: string read FAncestor;
    /// <summary>Alle Objekte außer dem Formular selbst und Collection-Einträgen.</summary>
    property Components: TArray<TFormComponent> read FComponents;
    property Events: TArray<TFormEvent> read FEvents;
    property References: TArray<TFormModuleReference> read FReferences;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.Parser;

{ TFormModel }

constructor TFormModel.Create(const AFormText, AUnitText: string);
begin
  Create(AFormText, AUnitText, '');
end;

constructor TFormModel.Create(const AFormText: string);
begin
  Create(AFormText, '', '');
end;

constructor TFormModel.Create(const AFormText, AUnitText, AUnitFile: string);
var
  mSymbol: TIndexSymbol;
begin
  inherited Create;
  // Binäre Formulare liest der Parser über die Umwandlung in Text (#122).
  FBinary := IsBinary(AFormText);
  FDocument := TDfmParser.Parse(AFormText);
  if AUnitText <> '' then
  begin
    FUnit := TIndexExtractor.ExtractText(AUnitText, AUnitFile, nil);
    FHasUnit := True;
    for mSymbol in FUnit.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.ClassType) and (mSymbol.Container = '') and
        SameText(mSymbol.Name, FormClass) and (Length(mSymbol.Ancestors) > 0) then
      begin
        FAncestor := mSymbol.Ancestors[0];
      end;
    end;
  end;
  if FDocument.Root <> nil then
  begin
    Collect(FDocument.Root);
  end;
end;

destructor TFormModel.Destroy;
begin
  FDocument.Free;
  inherited;
end;

class function TFormModel.IsBinary(const AText: string): Boolean;
begin
  // Binäre DFMs beginnen mit der Signatur "TPF0", gefolgt von Längenbytes.
  Result := StartsStr('TPF0', AText) or StartsStr(#$FF#$0A#$00, AText);
end;

function TFormModel.GetFormClass: string;
begin
  if (FDocument <> nil) and (FDocument.Root <> nil) then
  begin
    Result := FDocument.Root.TypeName;
  end
  else
  begin
    Result := '';
  end;
end;

function TFormModel.FindMember(const AName: string; AKinds: TIndexSymbolKinds; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  Result := False;
  if not FHasUnit then
  begin
    Exit;
  end;
  for mSymbol in FUnit.Symbols do
  begin
    if (mSymbol.Kind in AKinds) and SameText(mSymbol.Container, FormClass) and SameText(mSymbol.Name, AName) then
    begin
      ASymbol := mSymbol;
      // Die Deklaration in der Klasse kommt vor dem Rumpf; sie zählt.
      Exit(True);
    end;
  end;
end;

/// <summary>Wert der Form Modul.Komponente (zwei Bezeichner mit Punkt)?</summary>
function SplitModuleReference(const AValue: string; out AModule, AComponent: string): Boolean;
var
  mDot, mIndex: Integer;
begin
  Result := False;
  mDot := Pos('.', AValue);
  if (mDot < 2) or (mDot = Length(AValue)) or (PosEx('.', AValue, mDot + 1) > 0) then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(AValue) do
  begin
    if not CharInSet(AValue[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
    begin
      Exit;
    end;
  end;
  if not CharInSet(AValue[1], ['A'..'Z', 'a'..'z', '_']) or
    not CharInSet(AValue[mDot + 1], ['A'..'Z', 'a'..'z', '_']) then
  begin
    Exit;
  end;
  AModule := Copy(AValue, 1, mDot - 1);
  AComponent := Copy(AValue, mDot + 1, MaxInt);
  Result := True;
end;

procedure TFormModel.Collect(AObject: TDfmObject);
var
  mComponent: TFormComponent;
  mEvent: TFormEvent;
  mReference: TFormModuleReference;
  mItem: TDfmProperty;
  mChild: TDfmObject;
begin
  if (AObject <> FDocument.Root) and (AObject.Kind <> TDfmObjectKind.Item) and (AObject.Name <> '') then
  begin
    mComponent := Default(TFormComponent);
    mComponent.Obj := AObject;
    mComponent.IsInherited := AObject.Kind = TDfmObjectKind.Inherited_;
    mComponent.HasField := FindMember(AObject.Name, [TIndexSymbolKind.Field], mComponent.Field);
    FComponents := FComponents + [mComponent];
  end;
  for mItem in AObject.Properties do
  begin
    if mItem.IsEvent then
    begin
      mEvent := Default(TFormEvent);
      mEvent.Obj := AObject;
      mEvent.Event := mItem;
      mEvent.HasMethod := FindMember(mItem.Value, [TIndexSymbolKind.Method], mEvent.Method);
      FEvents := FEvents + [mEvent];
    end
    else if SplitModuleReference(mItem.Value, mReference.ModuleName, mReference.ComponentName) then
    begin
      mReference.Obj := AObject;
      mReference.Reference := mItem;
      FReferences := FReferences + [mReference];
    end;
  end;
  for mChild in AObject.Children do
  begin
    Collect(mChild);
  end;
end;

function TFormModel.FindComponent(const AName: string): TDfmObject;
var
  mComponent: TFormComponent;
begin
  for mComponent in FComponents do
  begin
    if SameText(mComponent.Obj.Name, AName) then
    begin
      Exit(mComponent.Obj);
    end;
  end;
  Result := nil;
end;

function TFormModel.IsOwnName(const AName: string): Boolean;
begin
  Result := ((FDocument.Root <> nil) and SameText(FDocument.Root.Name, AName)) or (FindComponent(AName) <> nil);
end;

function TFormModel.ForeignModules: TArray<string>;
var
  mReference: TFormModuleReference;
begin
  Result := nil;
  for mReference in FReferences do
  begin
    if not IsOwnName(mReference.ModuleName) and (IndexText(mReference.ModuleName, Result) < 0) then
    begin
      Result := Result + [mReference.ModuleName];
    end;
  end;
end;

class function TFormModel.ForeignModulesOf(const AFormText: string): TArray<string>;
var
  mModel: TFormModel;
begin
  Result := nil;
  if AFormText = '' then
  begin
    Exit;
  end;
  mModel := TFormModel.Create(AFormText);
  try
    Result := mModel.ForeignModules;
  finally
    mModel.Free;
  end;
end;

procedure SortByPosition(var ARanges: TArray<TTextRange>);
var
  mIndex, mInner: Integer;
  mSwap: TTextRange;
begin
  // Wenige Einträge: Einfügesortierung genügt.
  for mIndex := 1 to High(ARanges) do
  begin
    mInner := mIndex;
    while (mInner > 0) and ((ARanges[mInner - 1].StartPos.Line > ARanges[mInner].StartPos.Line) or
      ((ARanges[mInner - 1].StartPos.Line = ARanges[mInner].StartPos.Line) and
      (ARanges[mInner - 1].StartPos.Character > ARanges[mInner].StartPos.Character))) do
    begin
      mSwap := ARanges[mInner - 1];
      ARanges[mInner - 1] := ARanges[mInner];
      ARanges[mInner] := mSwap;
      Dec(mInner);
    end;
  end;
end;

function TFormModel.Occurrences(const AName: string): TArray<TTextRange>;
var
  mComponent: TFormComponent;
  mEvent: TFormEvent;
begin
  Result := nil;
  if FBinary or (FDocument = nil) then
  begin
    Exit;
  end;
  // Auch der Name des Formulars selbst (object Form1: TForm1).
  if (FDocument.Root <> nil) and SameText(FDocument.Root.Name, AName) then
  begin
    Result := Result + [FDocument.Root.NameRange];
  end;
  for mComponent in FComponents do
  begin
    if SameText(mComponent.Obj.Name, AName) then
    begin
      Result := Result + [mComponent.Obj.NameRange];
    end;
  end;
  for mEvent in FEvents do
  begin
    if SameText(mEvent.Event.Value, AName) then
    begin
      Result := Result + [mEvent.Event.ValueRange];
    end;
  end;
  SortByPosition(Result);
end;

end.
