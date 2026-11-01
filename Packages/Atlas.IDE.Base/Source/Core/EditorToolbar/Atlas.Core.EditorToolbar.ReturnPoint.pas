unit Atlas.Core.EditorToolbar.ReturnPoint;

// Atlas-Editorleiste (#1101), Rücksprung „Zurück zu Zeile …“ ohne VCL und
// OTA. Je Datei ein Ausgangspunkt:
// - Jumped merkt nach einem Abschnittssprung die Ausgangszeile samt Methode
//   (ContextAt). Weitere Abschnittssprünge ersetzen ihn nicht: Der Rücksprung
//   führt zum ersten Ausgangspunkt. Ein Sprung auf dieselbe Zeile merkt nichts.
// - LinesChanged verschiebt den Punkt wie eine Editor-Marke: Zeilen oberhalb
//   eingefügt oder gelöscht, die Zeilennummer wandert mit; liegt er in
//   gelöschten Zeilen, rückt er an die Stelle der Löschung (wie der
//   Navigationsverlauf #504).
// - Caret meldet die Cursorzeile. Kommt der Cursor nach dem Sprung zurück auf
//   die Ausgangszeile (Klick auf den Knopf, Alt+←, von Hand), ist der Punkt
//   erledigt und der Knopf verschwindet.
// - Forget beim Schließen der Datei, KeepOnly für alle noch offenen Dateien.
// Zeilen 0-basiert.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Outline.Model;

type
  TAtlasReturnPoint = record
    FileName: string;
    Line: Integer;
    /// <summary>Methode bzw. Routine der Ausgangszeile, z. B. „TfrmKunde.btnSpeichernClick“; leer ohne.</summary>
    Context: string;
    /// <summary>Der Cursor war seit dem Sprung woanders; erst dann zählt die Rückkehr auf die Zeile.</summary>
    Away: Boolean;
  end;

  TAtlasReturnPoints = class
  private
    FPoints: TDictionary<string, TAtlasReturnPoint>;
    class function KeyOf(const AFileName: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Abschnittssprung in AFileName von AFromLine nach ATargetLine; der erste Ausgangspunkt bleibt.
    /// </summary>
    procedure Jumped(const AFileName: string; AFromLine, ATargetLine: Integer; const AContext: string);
    function Find(const AFileName: string; out APoint: TAtlasReturnPoint): Boolean;
    /// <summary>ADelta Zeilen an AAnchor eingefügt (positiv) oder gelöscht (negativ).</summary>
    procedure LinesChanged(const AFileName: string; AAnchor, ADelta: Integer);
    /// <summary>Cursor in AFileName auf ALine; True, wenn der Rücksprung damit erledigt ist.</summary>
    function Caret(const AFileName: string; ALine: Integer): Boolean;
    procedure Forget(const AFileName: string);
    /// <summary>Punkte geschlossener Dateien vergessen.</summary>
    procedure KeepOnly(const AOpenFiles: TArray<string>);
    procedure Clear;
    function Count: Integer;
    /// <summary>Innerste Methode oder Routine, deren Bereich ALine enthält; Methodenrümpfe mit Besitzer
    /// („TFoo.Bar“). Leer außerhalb.</summary>
    class function ContextAt(const ANodes: TAtlasOutlineNodes; ALine: Integer): string; static;
  end;

implementation

uses
  Atlas.Core.Outline.Breadcrumbs;

{ TAtlasReturnPoints }

constructor TAtlasReturnPoints.Create;
begin
  inherited Create;
  FPoints := TDictionary<string, TAtlasReturnPoint>.Create;
end;

destructor TAtlasReturnPoints.Destroy;
begin
  FPoints.Free;
  inherited Destroy;
end;

class function TAtlasReturnPoints.KeyOf(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

procedure TAtlasReturnPoints.Jumped(const AFileName: string; AFromLine, ATargetLine: Integer;
  const AContext: string);
var
  Point: TAtlasReturnPoint;
begin
  if (AFileName = '') or (AFromLine = ATargetLine) or FPoints.ContainsKey(KeyOf(AFileName)) then
    Exit;
  Point.FileName := AFileName;
  Point.Line := AFromLine;
  Point.Context := AContext;
  Point.Away := True;
  FPoints.Add(KeyOf(AFileName), Point);
end;

function TAtlasReturnPoints.Find(const AFileName: string; out APoint: TAtlasReturnPoint): Boolean;
begin
  Result := FPoints.TryGetValue(KeyOf(AFileName), APoint);
  if not Result then
    APoint := Default(TAtlasReturnPoint);
end;

procedure TAtlasReturnPoints.LinesChanged(const AFileName: string; AAnchor, ADelta: Integer);
var
  Point: TAtlasReturnPoint;
begin
  if (ADelta = 0) or not FPoints.TryGetValue(KeyOf(AFileName), Point) or (Point.Line <= AAnchor) then
    Exit;
  if (ADelta < 0) and (Point.Line <= AAnchor - ADelta) then
    Point.Line := AAnchor
  else
    Point.Line := Point.Line + ADelta;
  FPoints[KeyOf(AFileName)] := Point;
end;

function TAtlasReturnPoints.Caret(const AFileName: string; ALine: Integer): Boolean;
var
  Point: TAtlasReturnPoint;
begin
  Result := False;
  if not FPoints.TryGetValue(KeyOf(AFileName), Point) then
    Exit;
  if ALine <> Point.Line then
  begin
    if not Point.Away then
    begin
      Point.Away := True;
      FPoints[KeyOf(AFileName)] := Point;
    end;
    Exit;
  end;
  if not Point.Away then
    Exit;
  FPoints.Remove(KeyOf(AFileName));
  Result := True;
end;

procedure TAtlasReturnPoints.Forget(const AFileName: string);
begin
  FPoints.Remove(KeyOf(AFileName));
end;

procedure TAtlasReturnPoints.KeepOnly(const AOpenFiles: TArray<string>);
var
  Open: TDictionary<string, Boolean>;
  FileName, Key: string;
begin
  Open := TDictionary<string, Boolean>.Create;
  try
    for FileName in AOpenFiles do
      Open.AddOrSetValue(KeyOf(FileName), True);
    for Key in FPoints.Keys.ToArray do
      if not Open.ContainsKey(Key) then
        FPoints.Remove(Key);
  finally
    Open.Free;
  end;
end;

procedure TAtlasReturnPoints.Clear;
begin
  FPoints.Clear;
end;

function TAtlasReturnPoints.Count: Integer;
begin
  Result := FPoints.Count;
end;

class function TAtlasReturnPoints.ContextAt(const ANodes: TAtlasOutlineNodes; ALine: Integer): string;
var
  Index, Best: Integer;
begin
  Best := -1;
  for Index := 0 to High(ANodes) do
  begin
    if not (ANodes[Index].Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) then
      Continue;
    if (ALine < ANodes[Index].StartLine) or (ALine > ANodes[Index].EndLine) then
      Continue;
    // Die innerste: der späteste Anfang.
    if (Best < 0) or (ANodes[Index].StartLine >= ANodes[Best].StartLine) then
      Best := Index;
  end;
  // Deklaration in einer Klasse mit Besitzer davor, wie beim Rumpf („TFoo.Bar“).
  Result := TAtlasBreadcrumbs.QualifiedName(ANodes, Best);
end;

end.
