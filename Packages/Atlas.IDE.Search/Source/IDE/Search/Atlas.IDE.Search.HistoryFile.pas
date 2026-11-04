unit Atlas.IDE.Search.HistoryFile;

// Such- und Ersetzen-Verlauf der Atlas-Suche (#893) in %APPDATA%\Atlas\search-history.json über Neustarts
// (TAtlasDataFile). Ist die Datei nicht lesbar, beginnt der Verlauf leer und die Datei wird nicht überschrieben.

interface

uses
  Atlas.Core.Search.History;

type
  TAtlasIdeSearchHistories = class
  private
    FSearch: TAtlasSearchHistory;
    FReplace: TAtlasSearchHistory;
    // Datei nicht lesbar: nicht überschreiben.
    FKept: Boolean;
  public
    constructor Create(ACapacity: Integer);
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    /// <summary>Verlauf kürzen; 0 = aus.</summary>
    procedure SetCapacity(ACapacity: Integer);
    property Search: TAtlasSearchHistory read FSearch;
    property Replace: TAtlasSearchHistory read FReplace;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Files.DataFile;

const
  cHistoryKind = 'Suchverlauf';

function HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'Atlas'), 'search-history.json');
end;

constructor TAtlasIdeSearchHistories.Create(ACapacity: Integer);
begin
  inherited Create;
  FSearch := TAtlasSearchHistory.Create(ACapacity);
  FReplace := TAtlasSearchHistory.Create(ACapacity);
end;

destructor TAtlasIdeSearchHistories.Destroy;
begin
  FreeAndNil(FSearch);
  FreeAndNil(FReplace);
  inherited Destroy;
end;

procedure TAtlasIdeSearchHistories.Load;
var
  mSearch, mReplace: TAtlasSearchHistory;
begin
  mSearch := FSearch;
  mReplace := FReplace;
  // Gesperrt: leer beginnen und die Datei nicht überschreiben; TAtlasDataFile protokolliert das ohne Pfad.
  FKept := not TAtlasDataFile.Writable(TAtlasDataFile.Load(HistoryFile, cHistoryKind,
    function(const AText: string): Boolean
    begin
      Result := TAtlasSearchHistories.FromText(AText, mSearch, mReplace);
    end));
  if FKept then
  begin
    FSearch.Clear;
    FReplace.Clear;
  end;
end;

procedure TAtlasIdeSearchHistories.Save;
begin
  if FKept then
  begin
    Exit;
  end;
  try
    TAtlasDataFile.Write(HistoryFile, TAtlasSearchHistories.ToText(FSearch, FReplace));
  except
    on E: Exception do
      TAtlasDataFile.ReportNotWritten(cHistoryKind, E);
  end;
end;

procedure TAtlasIdeSearchHistories.SetCapacity(ACapacity: Integer);
begin
  FSearch.Capacity := ACapacity;
  FReplace.Capacity := ACapacity;
end;

end.
