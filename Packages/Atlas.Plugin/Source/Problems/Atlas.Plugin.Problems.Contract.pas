unit Atlas.Plugin.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.
// TAtlasIdeError (#1819): ein Fehler aus Error Insight der IDE, roh wie in
// TOTAError; das Modul Prüfregeln liefert ihn über IAtlasIdeErrors
// (Atlas.IDE.Base.Foundation.Rules), umgerechnet wird in Atlas.Core.Problems.IdeErrors.

interface

uses
  Atlas.Plugin.Lsp.Contract;

type
  /// <summary>Liegt im Lsp-Feature (die Protokollschicht liegt unten); Alias für bestehende Nutzer.</summary>
  TAtlasProblemSeverity = Atlas.Plugin.Lsp.Contract.TAtlasProblemSeverity;
  TAtlasProblem = Atlas.Plugin.Lsp.Contract.TAtlasProblem;
  TAtlasProblemRelated = Atlas.Plugin.Lsp.Contract.TAtlasProblemRelated;

  /// <summary>Ein Fehler aus Error Insight der IDE (#1819), Werte wie in TOTAError: Zeilen 1-basiert, Spalten
  /// (CharIndex) wie geliefert, Severity roh.</summary>
  TAtlasIdeError = record
    Text: string;
    StartLine: Integer;
    StartCharIndex: Integer;
    StopLine: Integer;
    StopCharIndex: Integer;
    Severity: Integer;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Spalte „Art“: Error (auch Bug), Warnung, Info (information und hint).</summary>
  TAtlasFindingKind = (Error, Warning, Info);
  TAtlasFindingCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot, Compiler, Other);
  /// <summary>Stufe einer Datei (#1108): Datei des oberen Editors, in der IDE geöffnet, nicht geöffnet.</summary>
  TAtlasFindingTier = (Active, Open, Closed);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein Befund im Fenster „Atlas-Prüfung“ (#909); Spalte „Quelle“ liefert TAtlasIdeErrors.OriginText.
  /// </summary>
  TAtlasFinding = record
    FileName: string;
    Problem: TAtlasProblem;
    Kind: TAtlasFindingKind;
    Category: TAtlasFindingCategory;
    /// <summary>Betroffene Quelltextzeile ohne führenden und folgenden Leerraum; '' wenn unbekannt.</summary>
    LineText: string;
    /// <summary>Datei, Regel, Meldung und laufende Nummer: unabhängig von der Zeile.</summary>
    Key: string;
    /// <summary>Stufe der Datei (#1108); setzt TAtlasFindingsView aus den geöffneten Dateien.</summary>
    Tier: TAtlasFindingTier;
    /// <summary>"Unit1.pas:12:5" (1-basiert).</summary>
    function Location: string;
    /// <summary>Zeilentext, gekürzt auf AMax Zeichen mit „…“.</summary>
    function ShortLine(AMax: Integer): string;
    /// <summary>Regel-ID bzw. Meldungsnummer des Compilers.</summary>
    function Rule: string;
    /// <summary>Spalte „Compiler“ (#1024): "E2035", "E2034, E2035" oder "E2035 · Atlas + dcc" bei einem vom
    /// Build bestätigten Befund; '' ohne Code.</summary>
    function CompilerText: string;
    /// <summary>Meldung; ohne AShowCompilerCode (problems.showCompilerCode aus) ohne „(wie E2035)“.</summary>
    function MessageText(AShowCompilerCode: Boolean): string;
    /// <summary>AText ohne Leerraum außen, gekürzt auf AMax Zeichen mit „…“.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
  end;

  /// <summary>Sammelkorrektur (#1352) im Kontextmenü von „Atlas-Prüfung“; ein Modul stellt sie bereit (#1455, Modul
  /// Prüfregeln), das Fenster fragt laufende Module. Ohne Modul fehlt der Eintrag.</summary>
  IAtlasBulkFixer = interface
    ['{3B7E2D91-5A4C-4F68-9E13-C82D6A0F7B54}']
    /// <summary>Eintrag sichtbar (fix.bulk an).</summary>
    function CanFixAll: Boolean;
    /// <summary>Alle sicheren Treffer von ARule in den Dateien von AFindings (den angezeigten Befunden) korrigieren:
    /// Vorschau, dann die gewählten Dateien. Nur im Hauptthread.</summary>
    procedure FixAll(const ARule: string; const AFindings: TArray<TAtlasFinding>);
  end;

implementation

uses
  System.SysUtils;

{ TAtlasFinding }

function TAtlasFinding.Location: string;
begin
  Result := Format('%s:%d:%d', [ExtractFileName(FileName), Problem.StartLine + 1, Problem.StartCharacter + 1]);
end;

function TAtlasFinding.ShortLine(AMax: Integer): string;
begin
  Result := Shorten(LineText, AMax);
end;

function TAtlasFinding.Rule: string;
begin
  Result := Problem.Code;
end;

function TAtlasFinding.CompilerText: string;
begin
  Result := Problem.CompilerCodeText;
  if Problem.Confirmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasProblem.cConfirmedSource;
  end;
end;

function TAtlasFinding.MessageText(AShowCompilerCode: Boolean): string;
begin
  Result := Problem.Message;
  if not AShowCompilerCode then
  begin
    Result := TAtlasProblem.WithoutCompilerCode(Result);
  end;
end;

class function TAtlasFinding.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := AText.Trim;
  if (AMax > 1) and (Length(Result) > AMax) then
  begin
    Result := Copy(Result, 1, AMax - 1).TrimRight + '…';
  end;
end;

end.
