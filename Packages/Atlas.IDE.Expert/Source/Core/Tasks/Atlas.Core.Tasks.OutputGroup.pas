unit Atlas.Core.Tasks.OutputGroup;

// Register „Atlas-Aufgaben“ im Fenster Meldungen (#900), ohne Open Tools
// API: entscheidet beim Leeren, ob die Gruppe aus dem Fenster genommen wird.
// - Nur eine Gruppe, die Atlas angelegt hat, wird entfernt; sonst fragt
//   Atlas die IDE gar nicht.
// - Beim Beenden der IDE hat die IDE das Meldungsfenster samt Gruppen schon
//   abgebaut, bevor sie Atlas entlädt. Ein Aufruf von IOTAMessageServices
//   liest dann in coreide über nil; die Zugriffsverletzung brach den Abbau
//   der Projektaufgaben ab („Fehler beim Abbau: Tasks“). Dann nur vergessen.

interface

type
{$SCOPEDENUMS ON}
  TAtlasTaskOutputRelease = (None, Forget, Remove);
{$SCOPEDENUMS OFF}

  TAtlasTaskOutputGroup = record
  private
    FCreated: Boolean;
  public
    /// <summary>Atlas hat die Gruppe angelegt oder geholt, um hineinzuschreiben.</summary>
    procedure Used;
    /// <summary>Was beim Leeren geschieht; danach gilt die Gruppe als nicht angelegt.</summary>
    function Release(AIdeClosing: Boolean): TAtlasTaskOutputRelease;
    property Created: Boolean read FCreated;
  end;

implementation

{ TAtlasTaskOutputGroup }

procedure TAtlasTaskOutputGroup.Used;
begin
  FCreated := True;
end;

function TAtlasTaskOutputGroup.Release(AIdeClosing: Boolean): TAtlasTaskOutputRelease;
begin
  if not FCreated then
    Exit(TAtlasTaskOutputRelease.None);
  FCreated := False;
  if AIdeClosing then
    Result := TAtlasTaskOutputRelease.Forget
  else
    Result := TAtlasTaskOutputRelease.Remove;
end;

end.
