unit Atlas.Core.Assistants.Activity;

// Was KI-Assistenten gerade in der IDE tun, für die Anzeige „KI-Assistent
// aktiv“ im Statusfeld (#1906), ohne Windows und VCL. Die Eingänge melden
// Builds (Beginn, Ende) und angewendete Änderungen an offenen Dateien; View
// sagt, was das Feld zeigt:
// - Pause: KI-Assistenten angehalten; das Feld bleibt stehen, damit man die
//   Pause wieder aufheben kann. Die Eingänge lehnen neue Aufträge mit Grund ab.
// - Building: ein Build für einen KI-Assistenten läuft.
// - Edited: ein KI-Assistent hat vor höchstens cEditShownMs eine offene Datei
//   geändert.
// - Idle: nichts davon; das Feld verschwindet.
// Die Zeit kommt vom Aufrufer (Tickzähler in Millisekunden).

interface

{$SCOPEDENUMS ON}

type
  TAtlasAssistantsActivityKind = (Idle, Paused, Building, Edited);

  /// <summary>Was die Anzeige zeigt.</summary>
  TAtlasAssistantsActivityView = record
    Kind: TAtlasAssistantsActivityKind;
    /// <summary>Name des KI-Assistenten (clientInfo.name des MCP-Clients); '' = unbekannt.</summary>
    Client: string;
    /// <summary>Projekt (Building) bzw. Datei (Edited) ohne Pfad; '' bei Idle und Paused.</summary>
    Subject: string;
  end;

  TAtlasAssistantsActivity = class
  public const
    /// <summary>So lange zeigt die Anzeige eine angewendete Änderung.</summary>
    cEditShownMs = 60000;
  private
    FPaused: Boolean;
    FBuilding: Boolean;
    FBuildProject: string;
    FBuildClient: string;
    FEdited: Boolean;
    FEditFile: string;
    FEditClient: string;
    FEditAt: UInt64;
  public
    /// <summary>Ein Build für AClient hat begonnen (AProject mit oder ohne Pfad).</summary>
    procedure BuildStarted(const AProject, AClient: string);
    /// <summary>Der laufende Build ist zu Ende (auch bei Fehler oder Ablehnung).</summary>
    procedure BuildEnded;
    /// <summary>AClient hat zum Zeitpunkt ANowMs die offene Datei AFileName geändert.</summary>
    procedure EditApplied(const AFileName, AClient: string; ANowMs: UInt64);
    /// <summary>Was die Anzeige zum Zeitpunkt ANowMs zeigt.</summary>
    function View(ANowMs: UInt64): TAtlasAssistantsActivityView;
    /// <summary>Pause für KI-Assistenten: neue Aufträge werden abgelehnt.</summary>
    property Paused: Boolean read FPaused write FPaused;
    /// <summary>Läuft gerade ein Build für einen KI-Assistenten?</summary>
    property Building: Boolean read FBuilding;
  end;

implementation

uses
  System.SysUtils;

/// <summary>Dateiname ohne Pfad; trennt an \ und /, damit Windows-Pfade auch unter Linux (Tests) gehen.</summary>
function NameOnly(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := APath;
  for mIndex := Length(APath) downto 1 do
  begin
    if CharInSet(APath[mIndex], ['\', '/']) then
    begin
      Result := Copy(APath, mIndex + 1, MaxInt);
      Exit;
    end;
  end;
end;

{ TAtlasAssistantsActivity }

procedure TAtlasAssistantsActivity.BuildStarted(const AProject, AClient: string);
begin
  FBuilding := True;
  FBuildProject := NameOnly(AProject);
  FBuildClient := AClient;
end;

procedure TAtlasAssistantsActivity.BuildEnded;
begin
  FBuilding := False;
  FBuildProject := '';
  FBuildClient := '';
end;

procedure TAtlasAssistantsActivity.EditApplied(const AFileName, AClient: string; ANowMs: UInt64);
begin
  FEdited := True;
  FEditFile := NameOnly(AFileName);
  FEditClient := AClient;
  FEditAt := ANowMs;
end;

function TAtlasAssistantsActivity.View(ANowMs: UInt64): TAtlasAssistantsActivityView;
begin
  Result := Default(TAtlasAssistantsActivityView);
  if FPaused then
  begin
    Result.Kind := TAtlasAssistantsActivityKind.Paused;
  end
  else if FBuilding then
  begin
    Result.Kind := TAtlasAssistantsActivityKind.Building;
    Result.Client := FBuildClient;
    Result.Subject := FBuildProject;
  end
  else if FEdited and (ANowMs >= FEditAt) and (ANowMs - FEditAt < cEditShownMs) then
  begin
    Result.Kind := TAtlasAssistantsActivityKind.Edited;
    Result.Client := FEditClient;
    Result.Subject := FEditFile;
  end;
end;

end.
