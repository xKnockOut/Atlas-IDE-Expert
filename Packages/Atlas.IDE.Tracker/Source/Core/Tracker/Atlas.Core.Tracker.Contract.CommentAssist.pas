unit Atlas.Core.Tracker.Contract.CommentAssist;

// Vertrag des Kommentar-Editors (#1278, #1443): was ein Kommentarfeld der
// Oberfläche von der IDE bekommt (IAtlasCommentAssist; Benutzer und Issues im
// Hintergrund, Werte der Platzhalter, Textbausteine, Entwurf). Umgesetzt in
// Atlas.IDE.Tracker.Adapters.CommentAssist; die Logik des Editors steht in
// Atlas.Core.Tracker.CommentEditor.

interface

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract;

type
  /// <summary>Werte der Platzhalter eines Textbausteins.</summary>
  TAtlasCommentValues = record
    /// <summary>Kennung des Issues ("ATL-123", "#753").</summary>
    Issue: string;
    Branch: string;
    /// <summary>Kurz-Hash bzw. "r42" (SVN).</summary>
    Commit: string;
    /// <summary>Version des aktiven Projekts ("1.2.0.0").</summary>
    Version: string;
    class function Create(const AIssue, ABranch, ACommit, AVersion: string): TAtlasCommentValues; static;
  end;

  TAtlasCommentSnippet = record
    Name: string;
    Text: string;
    class function Create(const AName, AText: string): TAtlasCommentSnippet; static;
  end;

  TAtlasCommentUsersDone = reference to procedure(const AUsers: TArray<TAtlasTrackerUser>);
  TAtlasCommentIssuesDone = reference to procedure(const AIssues: TArray<TAtlasTrackerIssue>);
  TAtlasCommentValuesDone = reference to procedure(const AValues: TAtlasCommentValues);

  /// <summary>Was ein Kommentarfeld von der IDE bekommt (#1278); gebunden an Tracker, Issue und Feld. Antworten
  /// kommen im Hauptthread; eine neue Anfrage derselben Art ersetzt die alte (deren Antwort kommt nie).</summary>
  IAtlasCommentAssist = interface
    ['{CC119861-A5FF-4CBA-9293-2E26C48FEA40}']
    /// <summary>Tracker des Issues (für die Auslöser).</summary>
    function Target: TAtlasTrackerTarget;
    /// <summary>Textbausteine aus issues.commentSnippets.</summary>
    function Snippets: TArray<TAtlasCommentSnippet>;
    /// <summary>Benutzer zu AText (Hintergrund); ohne Tracker oder Token eine leere Liste.</summary>
    procedure FindUsers(const AText: string; const ADone: TAtlasCommentUsersDone);
    /// <summary>Issues zu AQuery (Hintergrund; Recent ohne Netz).</summary>
    procedure FindIssues(const AQuery: TAtlasIssueSearchQuery; const ADone: TAtlasCommentIssuesDone);
    /// <summary>Werte der Platzhalter (Versionsverwaltung im Hintergrund).</summary>
    procedure Values(const ADone: TAtlasCommentValuesDone);
    /// <summary>Offene Anfragen verwerfen.</summary>
    procedure Cancel;
    function LoadDraft(out AText: string; out ASaved: TDateTime): Boolean;
    /// <summary>Entwurf speichern; nur Leerraum löscht ihn.</summary>
    procedure SaveDraft(const AText: string);
    procedure DeleteDraft;
  end;

implementation

{ TAtlasCommentValues }

class function TAtlasCommentValues.Create(const AIssue, ABranch, ACommit, AVersion: string): TAtlasCommentValues;
begin
  Result.Issue := Trim(AIssue);
  Result.Branch := Trim(ABranch);
  Result.Commit := Trim(ACommit);
  Result.Version := Trim(AVersion);
end;

{ TAtlasCommentSnippet }

class function TAtlasCommentSnippet.Create(const AName, AText: string): TAtlasCommentSnippet;
begin
  Result.Name := AName;
  Result.Text := AText;
end;

end.
