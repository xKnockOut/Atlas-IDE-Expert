unit Atlas.IDE.Tracker.Adapters.PaletteSearch;

// Issues in der Befehlspalette (#1270), Rolle Adapters:
// TAtlasIssuePaletteSourceAdapter erfüllt IAtlasPaletteSource aus
// Atlas.Core.Commands.Contract und reicht an TAtlasIdeIssueSearch
// (Atlas.IDE.Tracker.PaletteSearch) weiter. Anlegen nur in der Komposition
// des Moduls. Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Contract,
  Atlas.IDE.Tracker.PaletteSearch;

type
  /// <summary>Zusatzquelle der Palette über ASearch.</summary>
  TAtlasIssuePaletteSourceAdapter = class(TInterfacedObject, IAtlasPaletteSource)
  private
    FSearch: TAtlasIdeIssueSearch;
    FSearchRef: IInterface;
  public
    constructor Create(ASearch: TAtlasIdeIssueSearch);
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    procedure Changed(const APattern: string);
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    procedure Closed;
  end;

implementation

{ TAtlasIssuePaletteSourceAdapter }

constructor TAtlasIssuePaletteSourceAdapter.Create(ASearch: TAtlasIdeIssueSearch);
begin
  inherited Create;
  FSearch := ASearch;
  FSearchRef := ASearch;
end;

procedure TAtlasIssuePaletteSourceAdapter.Opened(const AShow: TProc<TAtlasPaletteGroup>);
begin
  FSearch.Opened(AShow);
end;

procedure TAtlasIssuePaletteSourceAdapter.Changed(const APattern: string);
begin
  FSearch.Changed(APattern);
end;

procedure TAtlasIssuePaletteSourceAdapter.Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
begin
  FSearch.Execute(AItem, AAction);
end;

procedure TAtlasIssuePaletteSourceAdapter.Closed;
begin
  FSearch.Closed;
end;

end.
