unit Atlas.UI.Diagnostics.Strings;

// Oberflächentexte der Prüfung auf einen Kommandozeilen-Compiler (#1822) auf Deutsch und Englisch. Die Sprache
// bestimmt `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit `Atlas.UI.Strings` nicht weiter
// wächst.

interface

{$SCOPEDENUMS ON}

type
  TAtlasDiagnosticsTextId = (
    EditionNoticeTitle, EditionNoticeText, EditionSettings, SettingsEditionCheck, EditionSetupLine);

  TAtlasDiagnosticsStrings = class
  public
    class function Text(AId: TAtlasDiagnosticsTextId): string; static;
  end;

implementation

uses
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDiagnosticsTextId] of string = (
    ('Kein Kommandozeilen-Compiler',
     'RAD Studio ohne Kommandozeilen-Compiler erkannt (Starter oder Community). Builds für KI-Assistenten laufen ' +
       'über die IDE; Projektaufgaben mit dcc oder MSBuild laufen hier nicht.',
     'Einstellungen',
     'Kommandozeilen-Compiler prüfen (Starter, Community)',
     'Diese Edition von RAD Studio hat keinen Kommandozeilen-Compiler: Builds für KI-Assistenten laufen über die ' +
       'IDE, Projektaufgaben mit dcc oder MSBuild nicht.'),
    ('No command-line compiler',
     'RAD Studio without a command-line compiler detected (Starter or Community). Builds for AI assistants run ' +
       'through the IDE; project tasks using dcc or MSBuild do not run here.',
     'Settings',
     'Check for a command-line compiler (Starter, Community)',
     'This edition of RAD Studio has no command-line compiler: builds for AI assistants run through the IDE, ' +
       'project tasks using dcc or MSBuild do not.'));

{ TAtlasDiagnosticsStrings }

class function TAtlasDiagnosticsStrings.Text(AId: TAtlasDiagnosticsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

end.
