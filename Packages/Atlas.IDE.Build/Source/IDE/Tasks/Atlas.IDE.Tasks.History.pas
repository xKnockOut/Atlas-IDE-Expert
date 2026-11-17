unit Atlas.IDE.Tasks.History;

// Verlauf der Projektaufgaben in tasks.json (TAtlasIdeTaskProjects.HistoryFile):
// letzter Lauf je Projekt und Aufgabe und ausgeblendete Befunde. Beim Anlegen
// gelesen; eine gesperrt gelesene Datei (Kept, etwa von einer zweiten IDE)
// wird nicht mit dem Stand dieser Sitzung überschrieben. Abgetrennt vom
// Läufer (TAtlasIdeTasks), der die Aufgaben startet.
// Nur im Hauptthread.

interface

uses
  Atlas.Core.Tasks.Runs;

type
  TAtlasIdeTaskHistory = class
  private
    FData: TAtlasTaskHistory;
    /// <summary>Gesperrt gelesen: nicht überschreiben.</summary>
    FKept: Boolean;
  public
    /// <summary>Liest den Verlauf aus tasks.json.</summary>
    constructor Create;
    destructor Destroy; override;
    /// <summary>Lauf ARun der Aufgabe im Projekt AProject merken und speichern.</summary>
    procedure Remember(const AProject: string; const ARun: TAtlasTaskRun);
    /// <summary>Befunde der Aufgabe AName im Projekt AKey ein- bzw. ausblenden und speichern; liefert, ob sie
    /// jetzt ausgeblendet sind.</summary>
    function ToggleHidden(const AKey, AName: string): Boolean;
    /// <summary>Verlauf zum Lesen (letzter Lauf, ausgeblendet).</summary>
    property Data: TAtlasTaskHistory read FData;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Files.DataFile,
  Atlas.IDE.Tasks.Projects;

const
  cHistoryWhat = 'Verlauf der Projektaufgaben';

/// <summary>Verlauf in ADestination laden; True, wenn die Datei gesperrt gelesen wurde.</summary>
function LoadInto(ADestination: TAtlasTaskHistory): Boolean;
begin
  Result := not TAtlasDataFile.Writable(TAtlasDataFile.Load(TAtlasIdeTaskProjects.HistoryFile, cHistoryWhat,
    function(const AText: string): Boolean
    begin
      Result := ADestination.FromJson(AText);
    end));
end;

/// <summary>Speichern; gesperrt gelesene Datei nicht mit dem Stand dieser Sitzung überschreiben.</summary>
procedure SaveHistory(AData: TAtlasTaskHistory; AKept: Boolean);
begin
  if AKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(TAtlasIdeTaskProjects.HistoryFile, AData.ToJson);
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cHistoryWhat, E);
  end;
end;

{ TAtlasIdeTaskHistory }

constructor TAtlasIdeTaskHistory.Create;
begin
  inherited Create;
  FData := TAtlasTaskHistory.Create;
  FKept := LoadInto(FData);
end;

destructor TAtlasIdeTaskHistory.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

procedure TAtlasIdeTaskHistory.Remember(const AProject: string; const ARun: TAtlasTaskRun);
begin
  FData.Remember(AProject, ARun);
  SaveHistory(FData, FKept);
end;

function TAtlasIdeTaskHistory.ToggleHidden(const AKey, AName: string): Boolean;
begin
  Result := not FData.IsHidden(AKey, AName);
  FData.SetHidden(AKey, AName, Result);
  SaveHistory(FData, FKept);
end;

end.
