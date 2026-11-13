unit Atlas.UI.Tracker.GitHubStrings;

// Oberflächentexte des GitHub-Anbieters im Tracker auf Deutsch und Englisch:
// Abschnitt „Abschluss“ im Beenden-Dialog mit Schließgrund (#2135). Eigene
// Unit neben Atlas.UI.Tracker.Strings, die an der Längengrenze steht; die
// Sprache bestimmt Base (`TAtlasStrings.Language`) wie dort.

interface

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasGitHubTextId = (
    EndClose, EndCloseCompleted, EndCloseNotPlanned, EndCloseDuplicate, EndCloseKeepOpen, EndDuplicateHint,
    EndDuplicateMissing, EndDuplicateUnknown, EndDuplicateComment, EndSendDuplicate, EndSendNotPlanned, PartClosed,
    PartClosedNotPlanned, PartClosedDuplicate, PartDuplicateFallback);

{$SCOPEDENUMS OFF}

  TAtlasGitHubStrings = class
  public
    class function Text(AId: TAtlasGitHubTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasGitHubTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasGitHubTextId] of string = (
    ('Abschluss:',
     'Erledigt',
     'Nicht geplant',
     'Duplikat von',
     'Offen lassen',
     'Original, z. B. #123',
     'Bitte das Original angeben (z. B. #123), nicht das Issue selbst.',
     'Das Original %s gibt es im Repository nicht.',
     'Duplikat von %s.',
     'Als Duplikat schließen',
     'Als nicht geplant schließen',
     'geschlossen',
     'als nicht geplant geschlossen',
     'als Duplikat von %s geschlossen',
     'GitHub nahm den Duplikat-Verweis nicht an: als nicht geplant geschlossen, Verweis als Kommentar'),
    ('Close as:',
     'Completed',
     'Not planned',
     'Duplicate of',
     'Keep open',
     'Original, e.g. #123',
     'Enter the original (e.g. #123), not this issue itself.',
     'The original %s does not exist in the repository.',
     'Duplicate of %s.',
     'Close as duplicate',
     'Close as not planned',
     'closed',
     'closed as not planned',
     'closed as duplicate of %s',
     'GitHub did not accept the duplicate link: closed as not planned, link added as a comment'));

{ TAtlasGitHubStrings }

class function TAtlasGitHubStrings.Text(AId: TAtlasGitHubTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasGitHubStrings.Fmt(AId: TAtlasGitHubTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
