unit Atlas.IDE.CodeInsight.Composition.Editing;

// Bearbeitungshilfen im Editor: Änderungsmarken (#507), Zeilen verschieben (#634), Blockkommentar (#703),
// Anweisung vervollständigen (#697), Kommentar und Muster fortsetzen (#696, #671), mehrere Einfügemarken (#589),
// Bezeichner mitziehen (#658), Markierung umschließen (#672), Einfügen mit uses (#515), Umschließung entfernen
// (#657), Ausdruckstyp (#689) und Methodenrümpfe in Deklarationsreihenfolge (#660). Teil „Commands“.

interface

/// <summary>Bearbeitungshilfen in Startreihenfolge anmelden.</summary>
procedure InstallEditing;
/// <summary>Bearbeitungshilfen in umgekehrter Reihenfolge abmelden.</summary>
procedure UninstallEditing;

implementation

uses
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.LineChanges,
  Atlas.IDE.Editor.LineMove,
  Atlas.IDE.Editor.BlockComment,
  Atlas.IDE.Editor.StatementCompletion,
  Atlas.IDE.Editor.CommentContinuation,
  Atlas.IDE.Editor.PatternContinuation,
  Atlas.IDE.Editor.MultiCursor,
  Atlas.IDE.Editor.LinkedEditing,
  Atlas.IDE.Editor.WrapSelection,
  Atlas.IDE.Editor.SmartPaste,
  Atlas.IDE.Editor.Unwrap,
  Atlas.IDE.Editor.ExpressionType,
  Atlas.IDE.Editor.MethodPlacement,
  Atlas.IDE.Editor.RegionFolds,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status;

/// <summary>Vervollständigung oder Platzhalter des Managers offen?</summary>
function CompletionBusy: Boolean;
begin
  Result := (Manager <> nil) and (Manager.CompletionVisible or Manager.PlaceholdersActive);
end;

function CompletionVisible: Boolean;
begin
  Result := (Manager <> nil) and Manager.CompletionVisible;
end;

/// <summary>Mehrere Einfügemarken (#589, experimentell): nie bei offener Vervollständigung, im Platzhalter-Modus
/// oder während Bezeichner mitgezogen werden (#658).</summary>
function MultiCursorBusy: Boolean;
begin
  Result := CompletionBusy or TAtlasIdeLinkedEditing.Active;
end;

/// <summary>Bezeichner live mitziehen (#658, experimentell): ebenso nie neben Vervollständigung, Platzhaltern und
/// mehreren Einfügemarken.</summary>
function LinkedEditingBusy: Boolean;
begin
  Result := CompletionBusy or TAtlasIdeMultiCursor.Active;
end;

/// <summary>Umschließen (#672) und Einfügen mit uses (#515): nie neben Vervollständigung, Platzhaltern, mehreren
/// Einfügemarken und dem Mitziehen von Bezeichnern.</summary>
function TypingBusy: Boolean;
begin
  Result := CompletionBusy or TAtlasIdeMultiCursor.Active or TAtlasIdeLinkedEditing.Active;
end;

procedure MultiCursorStatus(const AText, AHint: string);
begin
  SetStatusExtra('multiCursor', AText, AHint, nil);
end;

procedure LinkedEditingStatus(const AText, AHint: string);
begin
  SetStatusExtra('linkedEditing', AText, AHint, nil);
end;

function UnopenedPolicy: TAtlasUnopenedPolicy;
begin
  Result := TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits);
end;

/// <summary>Änderungsmarken (#507), Zeilen verschieben (#634), Blockkommentar (#703), Anweisung (#697), Kommentar
/// (#696) und Muster (#671) fortsetzen.</summary>
procedure InstallLineHelpers;
begin
  // Änderungsmarken und Zeilenhistorie (#507).
  TAtlasIdeLineChanges.Install(Warnings());
  // Zeilen verschieben und duplizieren (#634): Meldung ohne Nachbarmethode.
  TAtlasIdeLineMove.Install(Warnings());
  // Blockkommentar umschalten (#703): Meldung beim Ablehnen.
  TAtlasIdeBlockComment.Install(Warnings());
  // Anweisung vervollständigen (#697): Rumpf und case-Zweige vom Server.
  TAtlasIdeStatementCompletion.Install(ActiveSession, Warnings());
  // Kommentar beim Enter fortsetzen (#696): beobachtet Enter, ohne die Taste zu binden.
  TAtlasIdeCommentContinuation.Install;
  // Muster fortsetzen (#671): nach dem Kommentar, nie bei offener Vervollständigung.
  TAtlasIdePatternContinuation.Install(RunningSession, CompletionVisible);
end;

procedure InstallEditing;
begin
  InstallLineHelpers;
  TAtlasIdeMultiCursor.Install(MultiCursorBusy, MultiCursorStatus);
  TAtlasIdeLinkedEditing.Install(LinkedEditingBusy, RunningSession, LinkedEditingStatus);
  TAtlasIdeWrapSelection.Install(TypingBusy);
  // Einfügen mit uses-Ergänzung (#515, experimentell): Ergebnis nur in der Meldungsansicht.
  TAtlasIdeSmartPaste.Install(TypingBusy, RunningSession, MessageLines());
  // Umschließung entfernen (#657): Liste und Vorschau; Ergebnis in der Meldungsansicht.
  TAtlasIdeUnwrap.Install(RunningSession, MessageLines());
  // Typ des markierten Ausdrucks (#689): Tooltip und Hervorhebung; Fehler in der Meldungsansicht.
  TAtlasIdeExpressionType.Install(RunningSession, MessageLines());
  // Methodenrümpfe in Deklarationsreihenfolge (#660): neue Rümpfe an ihre Stelle, Befehl mit Vorschau.
  TAtlasIdeMethodPlacement.Install(RunningSession, MessageLines(), UnopenedPolicy);
  // Regionen beim Öffnen auf- oder zuklappen (#1814).
  TAtlasIdeRegionFolds.Install;
end;

procedure UninstallEditing;
begin
  TAtlasIdeLineChanges.Uninstall;
  TAtlasIdeLineMove.Uninstall;
  TAtlasIdeBlockComment.Uninstall;
  TAtlasIdeUnwrap.Uninstall;
  TAtlasIdeExpressionType.Uninstall;
  TAtlasIdeMethodPlacement.Uninstall;
  TAtlasIdeRegionFolds.Uninstall;
  TAtlasIdeSmartPaste.Uninstall;
  TAtlasIdeWrapSelection.Uninstall;
  TAtlasIdeLinkedEditing.Uninstall;
  TAtlasIdeMultiCursor.Uninstall;
  TAtlasIdePatternContinuation.Uninstall;
  TAtlasIdeCommentContinuation.Uninstall;
  TAtlasIdeStatementCompletion.Uninstall;
end;

end.
