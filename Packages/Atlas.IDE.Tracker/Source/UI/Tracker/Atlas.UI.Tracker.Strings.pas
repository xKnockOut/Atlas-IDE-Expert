unit Atlas.UI.Tracker.Strings;

// Gemeinsames der Oberflächentexte des Moduls Tracker (#1455). Die Texte selbst liegen je Feature neben dem
// Code in Atlas.UI.Tracker.<Feature>.Strings (Issue, Development, Board, Flow, Workflow, Time, Attach,
// NewIssue, Settings, MyIssues, Sprint, TestResults); die Sprache bestimmt Base (`TAtlasStrings.Language`).
// Texte, die auch Base, die Willkommensseite oder der Optionsdialog nutzen, bleiben in `Atlas.UI.Strings`.

interface

type
  TAtlasTrackerStrings = class
  public
    /// <summary>Oberfläche englisch: für Vorgaben, die der Sprache folgen (Textbausteine, Kommentar beim Beenden).
    /// </summary>
    class function English: Boolean; static;
  end;

implementation

uses
  Atlas.UI.Strings;

{ TAtlasTrackerStrings }

class function TAtlasTrackerStrings.English: Boolean;
begin
  Result := TAtlasStrings.Language = TAtlasLanguage.English;
end;

end.
