unit Atlas.Core.Assistants.Sessions;

// Assistenten dieser IDE-Sitzung (#2616), ohne Windows und VCL: Jeder Assistent (Client und Sitzung des
// MCP-Prozesses, TAtlasAssistantOrigin) bekommt beim ersten Auftrag eine Nummer in der Reihenfolge seines
// Auftretens. Aus der Nummer wählen KI-Protokoll und Randmarken die Farbe (Nummer modulo Zahl der Farben); so haben
// die ersten Assistenten verschiedene Farben, und ein Assistent behält seine, solange das Modul läuft. Unbekannte
// Herkunft (älterer Server) hat keine Nummer (-1) und wird grau gezeichnet.

interface

uses
  System.Generics.Collections,
  Atlas.Plugin.Style.Color,
  Atlas.Plugin.Style.Palette,
  Atlas.Text.AssistantOrigin;

type
  TAtlasAssistantSessions = class
  private
    FOrigins: TList<TAtlasAssistantOrigin>;
    function Find(const AOrigin: TAtlasAssistantOrigin): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Nummer von AOrigin ab 0; ein neuer Assistent bekommt die nächste. -1 für unbekannte Herkunft.
    /// </summary>
    function IndexOf(const AOrigin: TAtlasAssistantOrigin): Integer;
    /// <summary>Wie IndexOf, ohne neue Assistenten aufzunehmen: -1, wenn AOrigin noch keinen Auftrag hatte.
    /// </summary>
    function Known(const AOrigin: TAtlasAssistantOrigin): Integer;
    /// <summary>Farbe ab 0 für AIndex bei ACount Farben; -1 (unbekannt) bleibt -1.</summary>
    class function ColorIndex(AIndex, ACount: Integer): Integer; static;
    /// <summary>Farbe des Assistenten AIndex: die Töne der Platzhalter von AColors (deutlich verschieden, gegen
    /// den Grund lesbar), unbekannt gedämpft.</summary>
    class function ColorOf(AIndex: Integer; const AColors: TAtlasColors): TAtlasColor; static;
    function Count: Integer;
    /// <summary>Alle Assistenten in der Reihenfolge ihres Auftretens.</summary>
    function Origins: TArray<TAtlasAssistantOrigin>;
  end;

implementation

{ TAtlasAssistantSessions }

constructor TAtlasAssistantSessions.Create;
begin
  inherited Create;
  FOrigins := TList<TAtlasAssistantOrigin>.Create;
end;

destructor TAtlasAssistantSessions.Destroy;
begin
  FOrigins.Free;
  inherited Destroy;
end;

function TAtlasAssistantSessions.Find(const AOrigin: TAtlasAssistantOrigin): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FOrigins.Count - 1 do
  begin
    if FOrigins[mIndex].SameAs(AOrigin) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasAssistantSessions.IndexOf(const AOrigin: TAtlasAssistantOrigin): Integer;
var
  mStored: TAtlasAssistantOrigin;
begin
  if not AOrigin.IsKnown then
  begin
    Exit(-1);
  end;
  Result := Find(AOrigin);
  if Result >= 0 then
  begin
    // Name erst später bekannt (Sitzung zuerst): nachtragen.
    mStored := FOrigins[Result];
    if (mStored.Client = '') and (AOrigin.Client <> '') then
    begin
      mStored.Client := AOrigin.Client;
      FOrigins[Result] := mStored;
    end;
    Exit;
  end;
  Result := FOrigins.Add(AOrigin);
end;

function TAtlasAssistantSessions.Known(const AOrigin: TAtlasAssistantOrigin): Integer;
begin
  Result := -1;
  if AOrigin.IsKnown then
  begin
    Result := Find(AOrigin);
  end;
end;

class function TAtlasAssistantSessions.ColorIndex(AIndex, ACount: Integer): Integer;
begin
  Result := -1;
  if (AIndex >= 0) and (ACount > 0) then
  begin
    Result := AIndex mod ACount;
  end;
end;

class function TAtlasAssistantSessions.ColorOf(AIndex: Integer; const AColors: TAtlasColors): TAtlasColor;
var
  mColor: Integer;
begin
  mColor := ColorIndex(AIndex, Length(AColors.Placeholders));
  if mColor < 0 then
  begin
    Exit(AColors.Muted);
  end;
  Result := AColors.Placeholders[Low(AColors.Placeholders) + mColor];
end;

function TAtlasAssistantSessions.Count: Integer;
begin
  Result := FOrigins.Count;
end;

function TAtlasAssistantSessions.Origins: TArray<TAtlasAssistantOrigin>;
begin
  Result := FOrigins.ToArray;
end;

end.
