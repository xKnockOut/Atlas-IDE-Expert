unit Atlas.Core.Designer.DataBindings;

// Datenkonstrukt der Auswahl für die Brotkrumenleiste der Datenbindung
// (#610), ohne VCL und Windows.
// - Eingabe: Objekte des Formulars und der geöffneten Datenmodule mit ihren
//   Verweisen (Connection, SQLConnection, DataSet, ProviderName,
//   MasterSource, DataSource, ListSource), Feldern (DataField, ListField,
//   KeyField) und, bei Datenmengen, den Namen der persistenten Felder.
//   ObjectsOf liest sie aus dem Formulartext (TAtlasFormModel), die IDE aus
//   den Komponenten im Designer. Ein Verweis „dmDaten.dsKunden“ zeigt in das
//   Datenmodul dmDaten.
// - Kanten laufen in Richtung der Daten: Verbindung → Datenmenge →
//   DataSource bzw. Provider → ClientDataSet (über ProviderName) →
//   DataSource → Steuerelemente und Detail-Datenmengen (MasterSource).
// - Konstrukt: alle Objekte, die über Kanten mit der Auswahl verbunden sind.
//   Stufe eines Objekts = längster Weg von einem Anfang des Konstrukts
//   (Kreise zählen nicht). Je Stufe ein Glied: die Auswahl, sonst das erste
//   Objekt auf dem Weg der Auswahl (Vorgänger und Nachfolger); Stufen ohne
//   Objekt auf dem Weg fallen weg. Mehrere Nachfolger auf dem Weg ergeben ein
//   Sammelglied („10 Verbraucher“). Jedes Glied kennt alle Objekte seiner
//   Stufe für die Liste am Pfeil.
// - Befunde: DataField ohne DataSource, Feld fehlt in der Datenmenge (nur,
//   wenn sie persistente Felder hat; ohne sie ist nichts bekannt und nichts
//   rot).

interface

uses
  Atlas.Core.Designer.FormModel;

type
{$SCOPEDENUMS ON}
  TAtlasBindingFinding = (None, NoDataSource, FieldMissing);
{$SCOPEDENUMS OFF}

  TAtlasBindingObject = record
    /// <summary>Formular oder Datenmodul, in dem das Objekt liegt.</summary>
    Module: string;
    Name: string;
    ClassName: string;
    Connection: string;
    SQLConnection: string;
    DataSet: string;
    /// <summary>Name des Providers (Text-Eigenschaft eines ClientDataSet).</summary>
    ProviderName: string;
    MasterSource: string;
    DataSource: string;
    ListSource: string;
    DataField: string;
    ListField: string;
    KeyField: string;
    /// <summary>Persistente Felder einer Datenmenge; leer = unbekannt.</summary>
    Fields: TArray<string>;
  end;

  TAtlasBindingNode = record
    /// <summary>„Modul.Name“; eindeutig über alle Module.</summary>
    Id: string;
    /// <summary>Name, aus einem anderen Modul „Modul.Name“.</summary>
    Caption: string;
    Module: string;
    Name: string;
    ClassName: string;
    /// <summary>DataField bzw. ListField; leer ohne.</summary>
    Field: string;
    Finding: TAtlasBindingFinding;
    /// <summary>Fehlendes Feld bei FieldMissing, DataField bei NoDataSource.</summary>
    MissingField: string;
    /// <summary>Datenmenge, in der das Feld fehlt.</summary>
    DataSet: string;
  end;

  TAtlasBindingCrumb = record
    Level: Integer;
    /// <summary>Gezeigtes Objekt der Stufe: die Auswahl oder das erste Objekt auf ihrem Weg.</summary>
    Head: TAtlasBindingNode;
    /// <summary>Alle Objekte der Stufe im Konstrukt, Head eingeschlossen.</summary>
    Members: TArray<TAtlasBindingNode>;
    /// <summary>Objekte der Stufe auf dem Weg der Auswahl.</summary>
    OnPath: Integer;
    /// <summary>Head ist die Auswahl.</summary>
    Selected: Boolean;
    /// <summary>Sammelglied: mehrere Objekte auf dem Weg, die Auswahl nicht darunter.</summary>
    Many: Boolean;
    /// <summary>Gemeinsame Klasse der Objekte auf dem Weg; leer bei verschiedenen.</summary>
    CommonClass: string;
  end;

  TAtlasBindingTrail = record
    Crumbs: TArray<TAtlasBindingCrumb>;
    /// <summary>Objekte im Konstrukt: 0 = Auswahl unbekannt, 1 = keine Verbindungen.</summary>
    Size: Integer;
    /// <summary>Die Auswahl selbst (Befund für den Hinweis).</summary>
    Selected: TAtlasBindingNode;
  end;

  TAtlasDataBindings = class
  public
    /// <summary>Objekte des Formulartexts AObjects im Modul AModule (Persistente Felder an ihrer Datenmenge).
    /// </summary>
    class function ObjectsOf(const AModule: string; const AObjects: TArray<TAtlasFormObject>)
      : TArray<TAtlasBindingObject>; static;
    /// <summary>Glieder zur Auswahl ASelected (Name im Modul AModule) über alle Objekte AAll.</summary>
    class function Trail(const AAll: TArray<TAtlasBindingObject>; const AModule, ASelected: string)
      : TAtlasBindingTrail; static;
    /// <summary>Kennung der Objekte und ihrer Verweise, um Änderungen zu erkennen.</summary>
    class function Signature(const AAll: TArray<TAtlasBindingObject>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections;

type
  /// <summary>Objekte als Knoten mit Kanten in Richtung der Daten.</summary>
  TBindingGraph = class
  private const
    cUnknown = -1;
    cVisiting = -2;
  private
    FAll: TArray<TAtlasBindingObject>;
    FModule: string;
    FIndex: TDictionary<string, Integer>;
    FIns: TArray<TArray<Integer>>;
    FOuts: TArray<TArray<Integer>>;
    FDepth: TArray<Integer>;
    function Resolve(AFrom: Integer; const ARef: string): Integer;
    procedure Edge(AFrom: Integer; const ARef: string);
    function DepthOf(AIndex: Integer; const AMembers: TArray<Boolean>): Integer;
    function Reach(AStart: Integer; AForward, ABackward: Boolean): TArray<Boolean>;
    function CrumbAt(ALevel, ASelected: Integer; const AMembers, AOnPath: TArray<Boolean>;
      out ACrumb: TAtlasBindingCrumb): Boolean;
    function DataSetBehind(AFrom: Integer; const ASource: string): Integer;
    procedure CheckFields(var ANode: TAtlasBindingNode; AFrom: Integer; const ASource, AFields: string);
  public
    constructor Create(const AAll: TArray<TAtlasBindingObject>; const AModule: string);
    destructor Destroy; override;
    function IndexOf(const AModule, AName: string): Integer;
    function Node(AIndex: Integer): TAtlasBindingNode;
    function Trail(ASelected: Integer): TAtlasBindingTrail;
  end;

function IdOf(const AModule, AName: string): string;
begin
  Result := (AModule + '.' + AName).ToLower;
end;

function Value(const AObject: TAtlasFormObject; const APath: string): string;
var
  mText: string;
begin
  Result := '';
  if AObject.ValueOf(APath, Result) and TAtlasFormModel.StringValue(Result, mText) then
  begin
    Result := mText;
  end;
end;

function IsField(const AObject: TAtlasFormObject; out AFieldName: string): Boolean;
begin
  AFieldName := Value(AObject, 'FieldName');
  Result := (AFieldName <> '') and EndsText('Field', AObject.TypeName);
end;

function HasField(const ADataSet: TAtlasBindingObject; const AField: string): Boolean;
var
  mField: string;
begin
  if Length(ADataSet.Fields) = 0 then
  begin
    // Ohne persistente Felder ist nichts bekannt.
    Exit(True);
  end;
  for mField in ADataSet.Fields do
  begin
    if SameText(mField, AField) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TBindingGraph }

constructor TBindingGraph.Create(const AAll: TArray<TAtlasBindingObject>; const AModule: string);
var
  mIndex: Integer;
begin
  inherited Create;
  FAll := AAll;
  FModule := AModule;
  FIndex := TDictionary<string, Integer>.Create;
  SetLength(FIns, Length(FAll));
  SetLength(FOuts, Length(FAll));
  SetLength(FDepth, Length(FAll));
  for mIndex := 0 to High(FAll) do
  begin
    FIndex.AddOrSetValue(IdOf(FAll[mIndex].Module, FAll[mIndex].Name), mIndex);
  end;
  // Kanten vom Ziel des Verweises zum Objekt: in Richtung der Daten.
  for mIndex := 0 to High(FAll) do
  begin
    Edge(mIndex, FAll[mIndex].Connection);
    Edge(mIndex, FAll[mIndex].SQLConnection);
    Edge(mIndex, FAll[mIndex].DataSet);
    Edge(mIndex, FAll[mIndex].ProviderName);
    Edge(mIndex, FAll[mIndex].MasterSource);
    Edge(mIndex, FAll[mIndex].DataSource);
    Edge(mIndex, FAll[mIndex].ListSource);
  end;
end;

destructor TBindingGraph.Destroy;
begin
  FIndex.Free;
  inherited Destroy;
end;

function TBindingGraph.IndexOf(const AModule, AName: string): Integer;
begin
  if not FIndex.TryGetValue(IdOf(AModule, AName), Result) then
  begin
    Result := -1;
  end;
end;

function TBindingGraph.Resolve(AFrom: Integer; const ARef: string): Integer;
var
  mDot: Integer;
begin
  Result := -1;
  if ARef.Trim = '' then
  begin
    Exit;
  end;
  mDot := Pos('.', ARef);
  if mDot > 0 then
  begin
    Result := IndexOf(Copy(ARef, 1, mDot - 1), Copy(ARef, mDot + 1, MaxInt));
  end
  else
  begin
    Result := IndexOf(FAll[AFrom].Module, ARef.Trim);
  end;
end;

procedure TBindingGraph.Edge(AFrom: Integer; const ARef: string);
var
  mTarget, mExisting: Integer;
begin
  mTarget := Resolve(AFrom, ARef);
  if (mTarget < 0) or (mTarget = AFrom) then
  begin
    Exit;
  end;
  for mExisting in FOuts[mTarget] do
  begin
    if mExisting = AFrom then
    begin
      Exit;
    end;
  end;
  FOuts[mTarget] := FOuts[mTarget] + [AFrom];
  FIns[AFrom] := FIns[AFrom] + [mTarget];
end;

function TBindingGraph.DataSetBehind(AFrom: Integer; const ASource: string): Integer;
var
  mSource: Integer;
begin
  Result := -1;
  mSource := Resolve(AFrom, ASource);
  if mSource >= 0 then
  begin
    Result := Resolve(mSource, FAll[mSource].DataSet);
  end;
end;

procedure TBindingGraph.CheckFields(var ANode: TAtlasBindingNode; AFrom: Integer; const ASource, AFields: string);
var
  mSet: Integer;
  mField: string;
begin
  mSet := DataSetBehind(AFrom, ASource);
  if (mSet < 0) or (ANode.Finding <> TAtlasBindingFinding.None) then
  begin
    Exit;
  end;
  for mField in AFields.Split([';']) do
  begin
    if (mField.Trim <> '') and not HasField(FAll[mSet], mField.Trim) then
    begin
      ANode.Finding := TAtlasBindingFinding.FieldMissing;
      ANode.MissingField := mField.Trim;
      ANode.DataSet := Node(mSet).Caption;
      Exit;
    end;
  end;
end;

function TBindingGraph.Node(AIndex: Integer): TAtlasBindingNode;
var
  mObject: TAtlasBindingObject;
begin
  mObject := FAll[AIndex];
  Result := Default(TAtlasBindingNode);
  Result.Id := mObject.Module + '.' + mObject.Name;
  Result.Module := mObject.Module;
  Result.Name := mObject.Name;
  Result.ClassName := mObject.ClassName;
  Result.Caption := mObject.Name;
  if not SameText(mObject.Module, FModule) then
  begin
    Result.Caption := Result.Id;
  end;
  Result.Field := mObject.DataField;
  if Result.Field = '' then
  begin
    Result.Field := mObject.ListField;
  end;
  if (mObject.DataField <> '') and (mObject.DataSource = '') then
  begin
    Result.Finding := TAtlasBindingFinding.NoDataSource;
    Result.MissingField := mObject.DataField;
    Exit;
  end;
  CheckFields(Result, AIndex, mObject.DataSource, mObject.DataField);
  CheckFields(Result, AIndex, mObject.ListSource, mObject.ListField + ';' + mObject.KeyField);
end;

/// <summary>Noch nicht erreichte Nachbarn ANext markieren und auf den Stapel legen.</summary>
procedure Visit(const ANext: TArray<Integer>; var AReached: TArray<Boolean>; AStack: TStack<Integer>);
var
  mNext: Integer;
begin
  for mNext in ANext do
  begin
    if not AReached[mNext] then
    begin
      AReached[mNext] := True;
      AStack.Push(mNext);
    end;
  end;
end;

function TBindingGraph.Reach(AStart: Integer; AForward, ABackward: Boolean): TArray<Boolean>;
var
  mStack: TStack<Integer>;
  mIndex: Integer;
begin
  SetLength(Result, Length(FAll));
  Result[AStart] := True;
  mStack := TStack<Integer>.Create;
  try
    mStack.Push(AStart);
    while mStack.Count > 0 do
    begin
      mIndex := mStack.Pop;
      if AForward then
      begin
        Visit(FOuts[mIndex], Result, mStack);
      end;
      if ABackward then
      begin
        Visit(FIns[mIndex], Result, mStack);
      end;
    end;
  finally
    mStack.Free;
  end;
end;

function TBindingGraph.DepthOf(AIndex: Integer; const AMembers: TArray<Boolean>): Integer;
var
  mPrevious, mDepth: Integer;
begin
  if FDepth[AIndex] >= 0 then
  begin
    Exit(FDepth[AIndex]);
  end;
  if FDepth[AIndex] = cVisiting then
  begin
    // Kreis (etwa Query.DataSource auf die eigene DataSource): diese Kante zählt nicht.
    Exit(-1);
  end;
  FDepth[AIndex] := cVisiting;
  Result := 0;
  for mPrevious in FIns[AIndex] do
  begin
    if AMembers[mPrevious] then
    begin
      mDepth := DepthOf(mPrevious, AMembers);
      if mDepth + 1 > Result then
      begin
        Result := mDepth + 1;
      end;
    end;
  end;
  FDepth[AIndex] := Result;
end;

function TBindingGraph.CrumbAt(ALevel, ASelected: Integer; const AMembers, AOnPath: TArray<Boolean>;
  out ACrumb: TAtlasBindingCrumb): Boolean;
var
  mIndex, mHead: Integer;
begin
  ACrumb := Default(TAtlasBindingCrumb);
  ACrumb.Level := ALevel;
  mHead := -1;
  for mIndex := 0 to High(FAll) do
  begin
    if not AMembers[mIndex] or (FDepth[mIndex] <> ALevel) then
    begin
      Continue;
    end;
    ACrumb.Members := ACrumb.Members + [Node(mIndex)];
    if not AOnPath[mIndex] then
    begin
      Continue;
    end;
    Inc(ACrumb.OnPath);
    if ACrumb.OnPath = 1 then
    begin
      ACrumb.CommonClass := FAll[mIndex].ClassName;
    end
    else if not SameText(ACrumb.CommonClass, FAll[mIndex].ClassName) then
    begin
      ACrumb.CommonClass := '';
    end;
    if (mHead < 0) or (mIndex = ASelected) then
    begin
      mHead := mIndex;
    end;
  end;
  Result := mHead >= 0;
  if Result then
  begin
    ACrumb.Head := Node(mHead);
    ACrumb.Selected := mHead = ASelected;
    ACrumb.Many := (ACrumb.OnPath > 1) and not ACrumb.Selected;
  end;
end;

function TBindingGraph.Trail(ASelected: Integer): TAtlasBindingTrail;
var
  mMembers, mBefore, mAfter, mOnPath: TArray<Boolean>;
  mIndex, mLevel, mMax: Integer;
  mCrumb: TAtlasBindingCrumb;
begin
  Result := Default(TAtlasBindingTrail);
  Result.Selected := Node(ASelected);
  mMembers := Reach(ASelected, True, True);
  mBefore := Reach(ASelected, False, True);
  mAfter := Reach(ASelected, True, False);
  SetLength(mOnPath, Length(FAll));
  mMax := 0;
  for mIndex := 0 to High(FAll) do
  begin
    FDepth[mIndex] := cUnknown;
    mOnPath[mIndex] := mBefore[mIndex] or mAfter[mIndex];
  end;
  for mIndex := 0 to High(FAll) do
  begin
    if mMembers[mIndex] then
    begin
      Inc(Result.Size);
      mMax := Max(mMax, DepthOf(mIndex, mMembers));
    end;
  end;
  // Je Stufe ein Glied; Stufen ohne Objekt auf dem Weg der Auswahl fallen weg.
  for mLevel := 0 to mMax do
  begin
    if CrumbAt(mLevel, ASelected, mMembers, mOnPath, mCrumb) then
    begin
      Result.Crumbs := Result.Crumbs + [mCrumb];
    end;
  end;
end;

{ TAtlasDataBindings }

class function TAtlasDataBindings.ObjectsOf(const AModule: string; const AObjects: TArray<TAtlasFormObject>)
  : TArray<TAtlasBindingObject>;
var
  mObject: TAtlasFormObject;
  mItem: TAtlasBindingObject;
  mField: string;
  mIndex: Integer;
begin
  Result := nil;
  for mObject in AObjects do
  begin
    if (mObject.Depth = 0) or IsField(mObject, mField) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasBindingObject);
    mItem.Module := AModule;
    mItem.Name := mObject.Name;
    mItem.ClassName := mObject.TypeName;
    mItem.Connection := Value(mObject, 'Connection');
    mItem.SQLConnection := Value(mObject, 'SQLConnection');
    mItem.DataSet := Value(mObject, 'DataSet');
    mItem.ProviderName := Value(mObject, 'ProviderName');
    mItem.MasterSource := Value(mObject, 'MasterSource');
    mItem.DataSource := Value(mObject, 'DataSource');
    mItem.ListSource := Value(mObject, 'ListSource');
    mItem.DataField := Value(mObject, 'DataField');
    mItem.ListField := Value(mObject, 'ListField');
    mItem.KeyField := Value(mObject, 'KeyField');
    Result := Result + [mItem];
  end;
  // Persistente Felder stehen in der DFM als Objekte in ihrer Datenmenge.
  for mObject in AObjects do
  begin
    if not IsField(mObject, mField) then
    begin
      Continue;
    end;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Name, mObject.OwnerName) then
      begin
        Result[mIndex].Fields := Result[mIndex].Fields + [mField];
      end;
    end;
  end;
end;

class function TAtlasDataBindings.Trail(const AAll: TArray<TAtlasBindingObject>; const AModule, ASelected: string)
  : TAtlasBindingTrail;
var
  mGraph: TBindingGraph;
  mSelected: Integer;
begin
  Result := Default(TAtlasBindingTrail);
  mGraph := TBindingGraph.Create(AAll, AModule);
  try
    mSelected := mGraph.IndexOf(AModule, ASelected);
    if mSelected >= 0 then
    begin
      Result := mGraph.Trail(mSelected);
    end;
  finally
    mGraph.Free;
  end;
end;

class function TAtlasDataBindings.Signature(const AAll: TArray<TAtlasBindingObject>): string;
var
  mObject: TAtlasBindingObject;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mObject in AAll do
    begin
      mBuilder.Append('|').Append(mObject.Module).Append('.').Append(mObject.Name).Append(':')
        .Append(mObject.ClassName).Append('=').Append(mObject.Connection).Append(',').Append(mObject.SQLConnection)
        .Append(',').Append(mObject.DataSet).Append(',').Append(mObject.ProviderName).Append(',')
        .Append(mObject.MasterSource).Append(',').Append(mObject.DataSource).Append(',').Append(mObject.ListSource)
        .Append(',').Append(mObject.DataField).Append(',').Append(mObject.ListField).Append(',')
        .Append(mObject.KeyField).Append(',').Append(string.Join(';', mObject.Fields));
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
