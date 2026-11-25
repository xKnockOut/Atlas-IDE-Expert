unit Atlas.Core.Architecture.MapMarks;

// Aus den Daten der Architekturkarte (#1118) abgeleitete Markierungen, ohne
// VCL: zentrale Units, Kanten auf einem Zyklus und Kanten, die gegenüber dem
// gespeicherten Stand neu sind (#1121). Read rechnet sie bei neuen Daten
// einmal; die Karte fragt sie je Unit bzw. Kante beim Zeichnen ab. Ob sie
// gezeigt werden (Schalter), entscheidet TAtlasArchitectureMapState.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Architecture.Model;

type
  TAtlasArchitectureMapMarks = class
  private
    /// <summary>Je Unit in Model.Units: zentral.</summary>
    FCentral: TArray<Boolean>;
    /// <summary>Je Kante in Model.Edges: neu gegenüber dem gespeicherten Stand.</summary>
    FAddedEdges: TArray<Boolean>;
    /// <summary>Kanten der Zyklen nach Quelle und Ziel (EdgeKey).</summary>
    FCycleEdges: TDictionary<Int64, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Markierungen aus AModel neu rechnen.</summary>
    procedure Read(const AModel: TAtlasArchitectureModel);
    function IsCentral(AUnit: Integer): Boolean;
    /// <summary>Kante AEdge (Nummer in Model.Edges) ist neu gegenüber dem gespeicherten Stand.</summary>
    function IsAdded(AEdge: Integer): Boolean;
    /// <summary>Kante liegt auf einem Zyklus.</summary>
    function OnCycle(const AEdge: TAtlasArchEdge): Boolean;
  end;

implementation

const
  // Die Quelle steht in den oberen 32 Bit des Schlüssels, das Ziel in den unteren.
  cSourceShift = 32;

function EdgeKey(ASource, ATarget: Integer): Int64;
begin
  Result := Int64(ASource) shl cSourceShift or Cardinal(ATarget);
end;

{ TAtlasArchitectureMapMarks }

constructor TAtlasArchitectureMapMarks.Create;
begin
  inherited Create;
  FCycleEdges := TDictionary<Int64, Boolean>.Create;
end;

destructor TAtlasArchitectureMapMarks.Destroy;
begin
  FCycleEdges.Free;
  inherited Destroy;
end;

procedure TAtlasArchitectureMapMarks.Read(const AModel: TAtlasArchitectureModel);
var
  mMember: Integer;
  mCycle: TAtlasArchCycle;
  mLink: TAtlasArchLink;
begin
  FCentral := nil;
  SetLength(FCentral, Length(AModel.Units));
  for mMember in AModel.Central do
  begin
    FCentral[mMember] := True;
  end;
  FCycleEdges.Clear;
  for mCycle in AModel.Cycles do
  begin
    for mLink in mCycle.Edges do
    begin
      FCycleEdges.AddOrSetValue(EdgeKey(mLink.Source, mLink.Target), True);
    end;
  end;
  FAddedEdges := nil;
  SetLength(FAddedEdges, Length(AModel.Edges));
  for mMember in AModel.Comparison.AddedEdges do
  begin
    if (mMember >= 0) and (mMember <= High(FAddedEdges)) then
    begin
      FAddedEdges[mMember] := True;
    end;
  end;
end;

function TAtlasArchitectureMapMarks.IsCentral(AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(FCentral)) and FCentral[AUnit];
end;

function TAtlasArchitectureMapMarks.IsAdded(AEdge: Integer): Boolean;
begin
  Result := (AEdge >= 0) and (AEdge < Length(FAddedEdges)) and FAddedEdges[AEdge];
end;

function TAtlasArchitectureMapMarks.OnCycle(const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := FCycleEdges.ContainsKey(EdgeKey(AEdge.Source, AEdge.Target));
end;

end.
