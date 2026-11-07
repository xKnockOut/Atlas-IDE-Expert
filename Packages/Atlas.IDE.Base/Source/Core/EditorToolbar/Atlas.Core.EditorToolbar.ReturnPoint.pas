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
  mPoint: TAtlasReturnPoint;
begin
  if (AFileName = '') or (AFromLine = ATargetLine) or FPoints.ContainsKey(KeyOf(AFileName)) then
  begin
    Exit;
  end;
  mPoint.FileName := AFileName;
  mPoint.Line := AFromLine;
  mPoint.Context := AContext;
  mPoint.Away := True;
  FPoints.Add(KeyOf(AFileName), mPoint);
end;

function TAtlasReturnPoints.Find(const AFileName: string; out APoint: TAtlasReturnPoint): Boolean;
begin
  Result := FPoints.TryGetValue(KeyOf(AFileName), APoint);
  if not Result then
  begin
    APoint := Default(TAtlasReturnPoint);
  end;
end;

procedure TAtlasReturnPoints.LinesChanged(const AFileName: string; AAnchor, ADelta: Integer);
var
  mPoint: TAtlasReturnPoint;
begin
  if (ADelta = 0) or not FPoints.TryGetValue(KeyOf(AFileName), mPoint) or (mPoint.Line <= AAnchor) then
  begin
    Exit;
  end;
  if (ADelta < 0) and (mPoint.Line <= AAnchor - ADelta) then
  begin
    mPoint.Line := AAnchor;
  end
  else
  begin
    mPoint.Line := mPoint.Line + ADelta;
  end;
  FPoints[KeyOf(AFileName)] := mPoint;
end;

function TAtlasReturnPoints.Caret(const AFileName: string; ALine: Integer): Boolean;
var
  mPoint: TAtlasReturnPoint;
begin
  Result := False;
  if not FPoints.TryGetValue(KeyOf(AFileName), mPoint) then
  begin
    Exit;
  end;
  if ALine <> mPoint.Line then
  begin
    if not mPoint.Away then
    begin
      mPoint.Away := True;
      FPoints[KeyOf(AFileName)] := mPoint;
    end;
    Exit;
  end;
  if not mPoint.Away then
  begin
    Exit;
  end;
  FPoints.Remove(KeyOf(AFileName));
  Result := True;
end;

procedure TAtlasReturnPoints.Forget(const AFileName: string);
begin
  FPoints.Remove(KeyOf(AFileName));
end;

procedure TAtlasReturnPoints.KeepOnly(const AOpenFiles: TArray<string>);
var
  mOpen: TDictionary<string, Boolean>;
  mFileName, mKey: string;
begin
  mOpen := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AOpenFiles do
    begin
      mOpen.AddOrSetValue(KeyOf(mFileName), True);
    end;
    for mKey in FPoints.Keys.ToArray do
    begin
      if not mOpen.ContainsKey(mKey) then
      begin
        FPoints.Remove(mKey);
      end;
    end;
  finally
    mOpen.Free;
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
  mIndex, mBest: Integer;
begin
  mBest := -1;
  for mIndex := 0 to High(ANodes) do
  begin
    if not (ANodes[mIndex].Category in [TAtlasOutlineCategory.Method, TAtlasOutlineCategory.Routine]) then
    begin
      Continue;
    end;
    if (ALine < ANodes[mIndex].StartLine) or (ALine > ANodes[mIndex].EndLine) then
    begin
      Continue;
    end;
    // Die innerste: der späteste Anfang.
    if (mBest < 0) or (ANodes[mIndex].StartLine >= ANodes[mBest].StartLine) then
    begin
      mBest := mIndex;
    end;
  end;
  // Deklaration in einer Klasse mit Besitzer davor, wie beim Rumpf („TFoo.Bar“).
  Result := TAtlasBreadcrumbs.QualifiedName(ANodes, mBest);
end;

end.
