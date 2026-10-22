unit Atlas.Core.Files.DataFile;

// Datendateien des Plugins (Bericht N3): Favoriten, Verläufe, Lernstände, Projektübersicht, Lesezeichen,
// Notizen und die übrigen JSON-Ablagen.
//
// Ursache kaputter Dateien war das Schreiben: TFile.WriteAllText kürzt die Datei und schreibt sie neu, die
// Ablagen mit Nachbardatei löschten erst die alte und benannten dann um. Ein Absturz oder eine zweite IDE
// dazwischen hinterließ eine leere, halbe oder gar keine Datei, und ein Leser konnte einen halben Stand sehen.
// Write ersetzt jetzt atomar (TAtlasTextFile.Replace: erst daneben schreiben, dann in einem Schritt ersetzen),
// Load liest, ohne das Ersetzen zu blockieren (TAtlasTextFile.ReadAllBytes).
//
// Ist der Inhalt trotzdem unbrauchbar (von Hand bearbeitet, von einer älteren Fassung halb geschrieben), legt
// Load die Datei als "<Name>.defekt" daneben und schreibt eine Zeile ins Plugin-Protokoll, nur mit der Art der
// Ablage, ohne Pfad. Die Ablage beginnt neu, die alten Daten bleiben zum Nachsehen erhalten. Früher begann sie
// still leer und überschrieb die Datei beim nächsten Speichern.
//
// Lässt sich eine vorhandene Datei nicht lesen (gesperrt, Lesefehler), meldet Load Kept: Die Ablage arbeitet
// ohne ihren Inhalt und darf die Datei nicht überschreiben, sonst gingen deren Daten verloren. Das steht einmal
// je Art und Sitzung im Protokoll.
//
// Geschrieben wird UTF-8 ohne BOM, wie bei JSON üblich; gelesen wird mit und ohne BOM (frühere Fassungen
// schrieben eines).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  /// <summary>Ergebnis von TAtlasDataFile.Load.</summary>
  TAtlasDataLoad = (
    /// <summary>Keine Datei: Die Ablage beginnt leer und darf schreiben.</summary>
    Missing,
    /// <summary>Gelesen.</summary>
    Loaded,
    /// <summary>Inhalt unbrauchbar und als .defekt beiseitegelegt: Die Ablage beginnt leer und darf
    /// schreiben.</summary>
    Renewed,
    /// <summary>Vorhanden, aber nicht gelesen (gesperrt, Lesefehler, Fehler im Leser) oder nicht
    /// beiseitezulegen: Die Ablage beginnt leer und darf die Datei nicht überschreiben.</summary>
    Kept);

  /// <summary>Übernimmt den Text in die Ablage; False, wenn er unbrauchbar ist (kein gültiges JSON, falsche
  /// Form). Einzelne unbrauchbare Einträge überspringt die Ablage selbst.</summary>
  TAtlasDataParse = reference to function(const AText: string): Boolean;

  TAtlasDataFile = record
  public const
    DefectExtension = '.defekt';
  public
    /// <summary>Liest AFileName und gibt den Text an AParse. AKind benennt die Ablage im Protokoll
    /// (z. B. 'Favoriten'); Pfade stehen nie darin.</summary>
    class function Load(const AFileName, AKind: string; const AParse: TAtlasDataParse): TAtlasDataLoad; static;
    /// <summary>Darf die Ablage nach diesem Ergebnis von Load die Datei schreiben? Nur nicht bei Kept.</summary>
    class function Writable(ALoad: TAtlasDataLoad): Boolean; static;
    /// <summary>Text der Datei, UTF-8 mit oder ohne BOM. False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function TryRead(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Schreibt AText als UTF-8 ohne BOM und ersetzt die Datei atomar; legt den Ordner an. Fehler
    /// (Ordner, Datei von einem anderen Programm gesperrt) als Ausnahme.</summary>
    class procedure Write(const AFileName, AText: string); static;
    /// <summary>Benennt AFileName in AFileName + DefectExtension um (eine ältere .defekt-Datei wird in einem
    /// Schritt ersetzt) und protokolliert es mit AKind und AReason. False, wenn es nicht ging; das steht dann
    /// auch im Protokoll, außer die Datei ist inzwischen fort (ein anderer Leser hat sie beiseitegelegt).
    /// </summary>
    class function SetAside(const AFileName, AKind, AReason: string): Boolean; static;
    /// <summary>Protokolliert, dass die Datei der Art AKind nicht geschrieben werden konnte, einmal je Art und
    /// Sitzung: die Klasse der Ausnahme, deren Meldung den Pfad enthalten kann; bei EAtlasTextFileError (ohne
    /// Pfad) auch die Meldung.</summary>
    class procedure ReportNotWritten(const AKind: string; E: Exception); static;
    /// <summary>Vergisst, welche Arten schon als nicht lesbar bzw. nicht geschrieben gemeldet sind (für Tests).
    /// </summary>
    class procedure ForgetReports; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Diagnostics.Guard;

var
  ReportLock: TCriticalSection;
  /// <summary>Schon gemeldet: "k:" + Art für nicht lesbare, "w:" + Art für nicht geschriebene Dateien.</summary>
  Reported: TStringList;

/// <summary>Schreibt AText ins Protokoll, wenn AKey in dieser Sitzung noch nicht gemeldet ist.</summary>
procedure ReportOnce(const AKey, AText: string);
var
  First: Boolean;
begin
  ReportLock.Enter;
  try
    First := Reported.IndexOf(AKey) < 0;
    if First then
      Reported.Add(AKey);
  finally
    ReportLock.Leave;
  end;
  if First then
    TAtlasGuard.Log(AText);
end;

/// <summary>Eine Zeile, dass die Datei der Art AKind unverändert bleibt.</summary>
procedure ReportKept(const AKind, AReason: string);
begin
  ReportOnce('k:' + AKind, Format('Datendatei %s: %s; sie bleibt in dieser Sitzung unverändert', [AKind, AReason]));
end;

function TextOf(const ABytes: TBytes): string;
begin
  // Mit oder ohne BOM.
  if (Length(ABytes) >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Result := TEncoding.UTF8.GetString(ABytes, 3, Length(ABytes) - 3)
  else
    Result := TEncoding.UTF8.GetString(ABytes);
end;

class function TAtlasDataFile.TryRead(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if not FileExists(AFileName) then
    Exit;
  try
    AText := TextOf(TAtlasTextFile.ReadAllBytes(AFileName));
    Result := True;
  except
    // Fehlt inzwischen, gesperrt oder Lesefehler; Load unterscheidet das über FileExists.
    on EStreamError do
      AText := '';
  end;
end;

class function TAtlasDataFile.Load(const AFileName, AKind: string; const AParse: TAtlasDataParse): TAtlasDataLoad;
var
  Text, Reason: string;
begin
  if not TryRead(AFileName, Text) then
  begin
    // Zwischen Prüfen und Öffnen gelöscht: wie ohne Datei.
    if not FileExists(AFileName) then
      Exit(TAtlasDataLoad.Missing);
    ReportKept(AKind, 'gesperrt oder nicht lesbar');
    Exit(TAtlasDataLoad.Kept);
  end;
  try
    if AParse(Text) then
      Exit(TAtlasDataLoad.Loaded);
  except
    // Eine Ausnahme kann am Inhalt oder am Leser liegen: Die Datei bleibt, wie sie ist. Nur die Klasse, die
    // Meldung könnte Inhalt der Datei enthalten.
    on E: Exception do
    begin
      ReportKept(AKind, 'Fehler beim Lesen (' + E.ClassName + ')');
      Exit(TAtlasDataLoad.Kept);
    end;
  end;
  if Trim(Text) = '' then
    Reason := 'leer'
  else
    Reason := 'kein gültiger Inhalt';
  // Fort: Ein zweiter Leser (anderer Thread, zweite IDE) hat sie eben beiseitegelegt.
  if SetAside(AFileName, AKind, Reason) or not FileExists(AFileName) then
    Result := TAtlasDataLoad.Renewed
  else
    Result := TAtlasDataLoad.Kept;
end;

class function TAtlasDataFile.Writable(ALoad: TAtlasDataLoad): Boolean;
begin
  Result := ALoad <> TAtlasDataLoad.Kept;
end;

class procedure TAtlasDataFile.Write(const AFileName, AText: string);
var
  Folder: string;
begin
  Folder := ExtractFileDir(AFileName);
  if (Folder <> '') and not ForceDirectories(Folder) then
    raise EInOutError.Create('Ordner der Datendatei lässt sich nicht anlegen');
  TAtlasTextFile.Replace(AFileName, TEncoding.UTF8.GetBytes(AText));
end;

class function TAtlasDataFile.SetAside(const AFileName, AKind, AReason: string): Boolean;
var
  Target: string;
begin
  Target := AFileName + DefectExtension;
  // Eine ältere beiseitegelegte Datei wird in einem Schritt ersetzt: Die jüngere hat den neueren Stand. Erst
  // löschen, dann umbenennen konnte zwei Lesern die eben beiseitegelegte Datei kosten.
  Result := MoveFileEx(PChar(AFileName), PChar(Target), MOVEFILE_REPLACE_EXISTING);
  if Result then
    TAtlasGuard.Log(Format('Datendatei %s: %s; beiseitegelegt als *%s, Atlas beginnt sie neu',
      [AKind, AReason, DefectExtension]))
  else if FileExists(AFileName) then
    ReportKept(AKind, AReason + ', lässt sich nicht beiseitelegen');
end;

class procedure TAtlasDataFile.ReportNotWritten(const AKind: string; E: Exception);
var
  Reason: string;
begin
  Reason := E.ClassName;
  if E is EAtlasTextFileError then
    Reason := Reason + ': ' + TAtlasGuard.SafeMessage(E.Message);
  ReportOnce('w:' + AKind, Format('Datendatei %s nicht gespeichert (%s)', [AKind, Reason]));
end;

class procedure TAtlasDataFile.ForgetReports;
begin
  ReportLock.Enter;
  try
    Reported.Clear;
  finally
    ReportLock.Leave;
  end;
end;

initialization
  ReportLock := TCriticalSection.Create;
  Reported := TStringList.Create;
  Reported.CaseSensitive := False;

finalization
  FreeAndNil(Reported);
  FreeAndNil(ReportLock);

end.
