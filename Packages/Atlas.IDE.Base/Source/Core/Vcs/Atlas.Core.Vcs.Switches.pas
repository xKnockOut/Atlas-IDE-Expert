unit Atlas.Core.Vcs.Switches;

// Wechsel erkennen (#571): Branch-Wechsel (git checkout/switch, svn switch)
// und neue Revision (Commit, Pull, svn update). TAtlasVcsWatch merkt sich den
// letzten Stand einer Arbeitskopie; Check fragt git bzw. svn nur, wenn sich
// die billige Marke aus den Verwaltungsdateien (ChangeMarker) geändert hat.
// Check startet dann einen Prozess und gehört in einen Hintergrund-Thread;
// eine Instanz ist nicht für mehrere Threads gleichzeitig gedacht.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract;

type
  TAtlasVcsSwitches = class
  public
    /// <summary>Wechsel von AOld nach ANew. Ohne bekannten alten Stand (leer) None.</summary>
    class function Compare(const AOld, ANew: TAtlasVcsHead): TAtlasVcsSwitch; static;
  end;

  TAtlasVcsWatch = class
  private
    FVcs: IAtlasVersionControl;
    FMarker: string;
    FHead: TAtlasVcsHead;
    FKnown: Boolean;
  public
    constructor Create(const AVcs: IAtlasVersionControl);
    /// <summary>Erster Aufruf merkt den Stand und liefert None. Danach: None ohne Wechsel oder wenn git bzw.
    /// svn nicht antwortet (der alte Stand bleibt), sonst die Art des Wechsels.</summary>
    function Check: TAtlasVcsSwitch;
    /// <summary>Zuletzt bekannter Stand; leer vor dem ersten erfolgreichen Check.</summary>
    property Head: TAtlasVcsHead read FHead;
    property Known: Boolean read FKnown;
    property Vcs: IAtlasVersionControl read FVcs;
  end;

implementation

{ TAtlasVcsSwitches }

class function TAtlasVcsSwitches.Compare(const AOld, ANew: TAtlasVcsHead): TAtlasVcsSwitch;
begin
  if (AOld.Branch = '') and (AOld.Revision = '') and not AOld.Detached then
    Exit(TAtlasVcsSwitch.None);
  if (AOld.Branch <> ANew.Branch) or (AOld.Detached <> ANew.Detached) then
    Result := TAtlasVcsSwitch.Branch
  else if AOld.Revision <> ANew.Revision then
    Result := TAtlasVcsSwitch.Revision
  else
    Result := TAtlasVcsSwitch.None;
end;

{ TAtlasVcsWatch }

constructor TAtlasVcsWatch.Create(const AVcs: IAtlasVersionControl);
begin
  inherited Create;
  FVcs := AVcs;
  FHead := TAtlasVcsHead.Empty;
end;

function TAtlasVcsWatch.Check: TAtlasVcsSwitch;
var
  Marker: string;
  Current: TAtlasVcsHead;
begin
  Result := TAtlasVcsSwitch.None;
  Marker := FVcs.ChangeMarker;
  if FKnown and (Marker <> '') and (Marker = FMarker) then
    Exit;
  if FVcs.Head(Current) <> TAtlasVcsOutcome.Ok then
    Exit;
  if FKnown then
    Result := TAtlasVcsSwitches.Compare(FHead, Current);
  FHead := Current;
  FMarker := Marker;
  FKnown := True;
end;

end.
