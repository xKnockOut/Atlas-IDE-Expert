unit Atlas.Core.Debug.LeakFlow;

// Entscheidungen des Fensters „Atlas-Lecks“ (#1875) außerhalb von Bericht und Zeilen, ohne IDE prüfbar (#1967):
// wohin ein Doppelklick führt, welche Datei des Projekts eine Stelle meint, welche Vorgeschichte verglichen wird,
// Statuszeile und Ablage der Vorgeschichte. Atlas.IDE.Debug.Leaks fragt Debugger, Fenster und Server.

interface

uses
  Atlas.Text.LeakReport,
  Atlas.Core.Debug.LeakCapture,
  Atlas.Core.Debug.LeakView;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was ein Doppelklick auf eine Zeile öffnet: nichts, den Kandidaten des Servers, die Erzeugungsstelle
  /// einer Gruppe.</summary>
  TAtlasLeakOpen = (None, Place, Site);
  {$SCOPEDENUMS OFF}

  TAtlasLeakFlow = class
  public const
    /// <summary>Trenner zwischen Zusammenfassung und Hinweis in der Statuszeile.</summary>
    cStatusSeparator = '  ·  ';
  public
    class function OpenOf(const ARow: TAtlasLeakRow): TAtlasLeakOpen; static;
    /// <summary>Rahmen der Erzeugungsstelle (nur bei OpenOf = Site).</summary>
    class function SiteOf(const ARow: TAtlasLeakRow): TLeakFrame; static;
    /// <summary>Datei unter AFiles mit demselben Namen wie AFileName (ohne Ordner); '' ohne.</summary>
    class function FileNamed(const AFiles: TArray<string>; const AFileName: string): string; static;
    /// <summary>Vorgeschichte für den Vergleich: ohne Vergleich (ACompare False) gilt jeder Name als bisher
    /// unbekannt, „bekannt“ bleibt.</summary>
    class function Compared(const AHistory: TAtlasLeakHistory; ACompare: Boolean): TAtlasLeakHistory; static;
    /// <summary>„bekannt“ der Einträge nach AHistory.</summary>
    class procedure ApplyKnown(var AEntries: TArray<TAtlasLeakEntry>; const AHistory: TAtlasLeakHistory); static;
    /// <summary>Statuszeile: Zusammenfassung, dahinter ANote.</summary>
    class function StatusWith(const ASummary, ANote: string): string; static;
    /// <summary>Datei der Vorgeschichte im Ordner AFolder neben dem Projekt; '' ohne Projekt.</summary>
    class function HistoryPath(const AProject, AFolder, AName: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils;

{ TAtlasLeakFlow }

class function TAtlasLeakFlow.OpenOf(const ARow: TAtlasLeakRow): TAtlasLeakOpen;
begin
  Result := TAtlasLeakOpen.None;
  if ARow.Kind = TAtlasLeakRowKind.Place then
  begin
    Result := TAtlasLeakOpen.Place;
  end
  else if (ARow.Kind = TAtlasLeakRowKind.Group) and (ARow.Group.Site >= 0) then
  begin
    Result := TAtlasLeakOpen.Site;
  end;
end;

class function TAtlasLeakFlow.SiteOf(const ARow: TAtlasLeakRow): TLeakFrame;
begin
  Result := ARow.Group.Frames[ARow.Group.Site];
end;

class function TAtlasLeakFlow.FileNamed(const AFiles: TArray<string>; const AFileName: string): string;
var
  mFile: string;
begin
  for mFile in AFiles do
  begin
    if SameText(ExtractFileName(mFile), ExtractFileName(AFileName)) then
    begin
      Exit(mFile);
    end;
  end;
  Result := '';
end;

class function TAtlasLeakFlow.Compared(const AHistory: TAtlasLeakHistory; ACompare: Boolean): TAtlasLeakHistory;
begin
  Result := AHistory;
  if not ACompare then
  begin
    Result.Names := nil;
    Result.Counts := nil;
  end;
end;

class procedure TAtlasLeakFlow.ApplyKnown(var AEntries: TArray<TAtlasLeakEntry>; const AHistory: TAtlasLeakHistory);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AEntries) do
  begin
    AEntries[mIndex].Known := AHistory.IsKnown(AEntries[mIndex].Name);
  end;
end;

class function TAtlasLeakFlow.StatusWith(const ASummary, ANote: string): string;
begin
  Result := ASummary + cStatusSeparator + ANote;
end;

class function TAtlasLeakFlow.HistoryPath(const AProject, AFolder, AName: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(ExtractFileDir(AProject), AFolder), AName);
  end;
end;

end.
