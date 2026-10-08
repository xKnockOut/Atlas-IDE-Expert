unit BDLsp.Common.Dfm.FormModel;

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
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Dfm.Contract;

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
    constructor Create(const AFormText: string; const AUnitText: string = ''; const AUnitFile: string = '');
    destructor Destroy; override;
    /// <summary>Binäre Formulardatei (beginnt mit TPF0)?</summary>
    class function IsBinary(const AText: string): Boolean; static;
    /// <summary>Stellen, an denen AName als Komponentenname oder Ereignis-Handler vorkommt.</summary>
    function Occurrences(const AName: string): TArray<TTextRange>;
    /// <summary>Formularobjekt mit diesem Namen; nil ohne.</summary>
    function FindComponent(const AName: string): TDfmObject;
    /// <summary>Binär gespeichert; gelesen wird die Umwandlung in Text.</summary>
    property Binary: Boolean read FBinary;
    property Document: TDfmDocument read FDocument;
    /// <summary>Klasse des Formulars, z. B. TForm1; '' ohne Wurzelobjekt.</summary>
    property FormClass: string read GetFormClass;
    /// <summary>Vorfahr der Formularklasse laut Unit (z. B. TBasisForm bei geerbten Formularen); '' ohne Unit.</summary>
    property Ancestor: string read FAncestor;
    /// <summary>Alle Objekte außer dem Formular selbst und Collection-Einträgen.</summary>
    property Components: TArray<TFormComponent> read FComponents;
    property Events: TArray<TFormEvent> read FEvents;
    property References: TArray<TFormModuleReference> read FReferences;
  end;

implementation

uses
  System.StrUtils,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Dfm.Parser;

{ TFormModel }

constructor TFormModel.Create(const AFormText, AUnitText, AUnitFile: string);
var
  Symbol: TIndexSymbol;
begin
  inherited Create;
  // Binäre Formulare liest der Parser über die Umwandlung in Text (#122).
  FBinary := IsBinary(AFormText);
  FDocument := TDfmParser.Parse(AFormText);
  if AUnitText <> '' then
  begin
    FUnit := TIndexExtractor.ExtractText(AUnitText, AUnitFile, nil);
    FHasUnit := True;
    for Symbol in FUnit.Symbols do
      if (Symbol.Kind = TIndexSymbolKind.ClassType) and (Symbol.Container = '') and
        SameText(Symbol.Name, FormClass) and (Length(Symbol.Ancestors) > 0) then
        FAncestor := Symbol.Ancestors[0];
  end;
  if FDocument.Root <> nil then
    Collect(FDocument.Root);
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
    Result := FDocument.Root.TypeName
  else
    Result := '';
end;

function TFormModel.FindMember(const AName: string; AKinds: TIndexSymbolKinds; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not FHasUnit then
    Exit;
  for Symbol in FUnit.Symbols do
    if (Symbol.Kind in AKinds) and SameText(Symbol.Container, FormClass) and SameText(Symbol.Name, AName) then
    begin
      ASymbol := Symbol;
      // Die Deklaration in der Klasse kommt vor dem Rumpf; sie zählt.
      Exit(True);
    end;
end;

/// <summary>Wert der Form Modul.Komponente (zwei Bezeichner mit Punkt)?</summary>
function SplitModuleReference(const AValue: string; out AModule, AComponent: string): Boolean;
var
  Dot, Index: Integer;
begin
  Result := False;
  Dot := Pos('.', AValue);
  if (Dot < 2) or (Dot = Length(AValue)) or (PosEx('.', AValue, Dot + 1) > 0) then
    Exit;
  for Index := 1 to Length(AValue) do
    if not CharInSet(AValue[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit;
  if not CharInSet(AValue[1], ['A'..'Z', 'a'..'z', '_']) or
    not CharInSet(AValue[Dot + 1], ['A'..'Z', 'a'..'z', '_']) then
    Exit;
  AModule := Copy(AValue, 1, Dot - 1);
  AComponent := Copy(AValue, Dot + 1, MaxInt);
  Result := True;
end;

procedure TFormModel.Collect(AObject: TDfmObject);
var
  Component: TFormComponent;
  Event: TFormEvent;
  Reference: TFormModuleReference;
  Item: TDfmProperty;
  Child: TDfmObject;
begin
  if (AObject <> FDocument.Root) and (AObject.Kind <> TDfmObjectKind.Item) and (AObject.Name <> '') then
  begin
    Component := Default(TFormComponent);
    Component.Obj := AObject;
    Component.IsInherited := AObject.Kind = TDfmObjectKind.Inherited_;
    Component.HasField := FindMember(AObject.Name, [TIndexSymbolKind.Field], Component.Field);
    FComponents := FComponents + [Component];
  end;
  for Item in AObject.Properties do
    if Item.IsEvent then
    begin
      Event := Default(TFormEvent);
      Event.Obj := AObject;
      Event.Event := Item;
      Event.HasMethod := FindMember(Item.Value, [TIndexSymbolKind.Method], Event.Method);
      FEvents := FEvents + [Event];
    end
    else if SplitModuleReference(Item.Value, Reference.ModuleName, Reference.ComponentName) then
    begin
      Reference.Obj := AObject;
      Reference.Reference := Item;
      FReferences := FReferences + [Reference];
    end;
  for Child in AObject.Children do
    Collect(Child);
end;

function TFormModel.FindComponent(const AName: string): TDfmObject;
var
  Component: TFormComponent;
begin
  for Component in FComponents do
    if SameText(Component.Obj.Name, AName) then
      Exit(Component.Obj);
  Result := nil;
end;

procedure SortByPosition(var ARanges: TArray<TTextRange>);
var
  Index, Inner: Integer;
  Swap: TTextRange;
begin
  // Wenige Einträge: Einfügesortierung genügt.
  for Index := 1 to High(ARanges) do
  begin
    Inner := Index;
    while (Inner > 0) and ((ARanges[Inner - 1].StartPos.Line > ARanges[Inner].StartPos.Line) or
      ((ARanges[Inner - 1].StartPos.Line = ARanges[Inner].StartPos.Line) and
      (ARanges[Inner - 1].StartPos.Character > ARanges[Inner].StartPos.Character))) do
    begin
      Swap := ARanges[Inner - 1];
      ARanges[Inner - 1] := ARanges[Inner];
      ARanges[Inner] := Swap;
      Dec(Inner);
    end;
  end;
end;

function TFormModel.Occurrences(const AName: string): TArray<TTextRange>;
var
  Component: TFormComponent;
  Event: TFormEvent;
begin
  Result := nil;
  if FBinary or (FDocument = nil) then
    Exit;
  // Auch der Name des Formulars selbst (object Form1: TForm1).
  if (FDocument.Root <> nil) and SameText(FDocument.Root.Name, AName) then
    Result := Result + [FDocument.Root.NameRange];
  for Component in FComponents do
    if SameText(Component.Obj.Name, AName) then
      Result := Result + [Component.Obj.NameRange];
  for Event in FEvents do
    if SameText(Event.Event.Value, AName) then
      Result := Result + [Event.Event.ValueRange];
  SortByPosition(Result);
end;

end.
