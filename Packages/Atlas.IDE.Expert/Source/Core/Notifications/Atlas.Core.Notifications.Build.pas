unit Atlas.Core.Notifications.Build;

// Einträge der Quellen „Build fertig“ (#535) und „Hintergrundprüfung“ (#548)
// für die Benachrichtigungszentrale (#601), ohne VCL und Open Tools API: aus
// den Compilermeldungen eines Laufs (#528) Zahlen, Schwere, Art des Eintrags
// und die erste Fehlermeldung als Ziel für „Zum Fehler“. Die Texte setzt die
// IDE-Schicht in der Sprache der Oberfläche zusammen.
// - Build des Benutzers: immer ein Eintrag (Fehler rot, Warnungen gelb, sonst
//   Info); ohne lesbare Meldungen „fehlgeschlagen“ bzw. „erfolgreich“.
// - Build des Benutzers mit lesbaren Meldungen nach der Bewertung von #530
//   (FromVerdict, Atlas.Core.Build.Verdict): Meldungen in der Basislinie
//   zählen nicht; lassen build.zeroHints oder build.warningsAsErrors den
//   Build scheitern, ist der Eintrag rot (Rejected) mit „Zur Meldung“.
// - Hintergrundprüfung: nur bei Fehlern, und einmal „wieder fehlerfrei“, wenn
//   die vorige Prüfung desselben Projekts Fehler hatte; sonst nichts (sie
//   läuft nach jedem Speichern).

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Notifications.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Art des Eintrags: None = keiner; Errors/Warnings/Succeeded/Failed für Builds, CheckErrors und
  /// CheckClean für die Hintergrundprüfung; Rejected: der Compiler meldet Erfolg, die Bewertung von #530 nicht.
  /// </summary>
  TAtlasBuildNoticeKind = (None, Errors, Warnings, Succeeded, Failed, CheckErrors, CheckClean, Rejected);
{$SCOPEDENUMS OFF}

  TAtlasBuildNotice = record
    Kind: TAtlasBuildNoticeKind;
    Severity: TAtlasNotificationSeverity;
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    /// <summary>Warnungen und Hinweise in der Basislinie (#530), nicht gezählt.</summary>
    Baselined: Integer;
    /// <summary>Grund bei Rejected.</summary>
    Reason: TAtlasBuildVerdictReason;
    /// <summary>Erster Code aus build.warningsAsErrors bei Reason WarningsAsErrors.</summary>
    PromotedCode: string;
    /// <summary>Erste Meldung mit Schwere Fehler (Error oder Fatal) und Datei, bei FromVerdict die maßgebliche
    /// Meldung (TAtlasBuildVerdict.First); HasTarget False ohne.</summary>
    HasTarget: Boolean;
    Target: TAtlasCompilerMessage;
  end;

  TAtlasBuildNotices = class
  public
    /// <summary>Eintrag nach einem Lauf. ABackground: Hintergrundprüfung (#548); APreviousErrors: Fehler der
    /// vorigen Hintergrundprüfung desselben Projekts (-1 = unbekannt). AReadable: Meldungen waren lesbar.</summary>
    class function FromRun(const AMessages: TArray<TAtlasCompilerMessage>; ASucceeded, AReadable,
      ABackground: Boolean; APreviousErrors: Integer): TAtlasBuildNotice; static;
    /// <summary>Eintrag nach einem Build des Benutzers mit lesbaren Meldungen, bewertet nach #530.</summary>
    class function FromVerdict(const AMessages: TArray<TAtlasCompilerMessage>;
      const AVerdict: TAtlasBuildVerdict): TAtlasBuildNotice; static;
    /// <summary>Quelle des Eintrags: "check" für die Hintergrundprüfung, sonst "build".</summary>
    class function SourceOf(ABackground: Boolean): string; static;
  end;

implementation

uses
  Atlas.Core.Notifications.Sources;

{ TAtlasBuildNotices }

class function TAtlasBuildNotices.SourceOf(ABackground: Boolean): string;
begin
  if ABackground then
    Result := TAtlasNotificationSources.Check
  else
    Result := TAtlasNotificationSources.Build;
end;

class function TAtlasBuildNotices.FromRun(const AMessages: TArray<TAtlasCompilerMessage>; ASucceeded, AReadable,
  ABackground: Boolean; APreviousErrors: Integer): TAtlasBuildNotice;
var
  Item: TAtlasCompilerMessage;
begin
  Result := Default(TAtlasBuildNotice);
  Result.Severity := TAtlasNotificationSeverity.Info;
  for Item in AMessages do
    case Item.Severity of
      TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal:
        begin
          Inc(Result.Errors);
          if not Result.HasTarget and (Item.FileName <> '') then
          begin
            Result.HasTarget := True;
            Result.Target := Item;
          end;
        end;
      TAtlasCompilerSeverity.Warning:
        Inc(Result.Warnings);
      TAtlasCompilerSeverity.Hint:
        Inc(Result.Hints);
    end;
  if ABackground then
  begin
    if Result.Errors > 0 then
    begin
      Result.Kind := TAtlasBuildNoticeKind.CheckErrors;
      Result.Severity := TAtlasNotificationSeverity.Error;
    end
    else if AReadable and ASucceeded and (APreviousErrors > 0) then
      Result.Kind := TAtlasBuildNoticeKind.CheckClean
    else
      Result.Kind := TAtlasBuildNoticeKind.None;
    Exit;
  end;
  if Result.Errors > 0 then
  begin
    Result.Kind := TAtlasBuildNoticeKind.Errors;
    Result.Severity := TAtlasNotificationSeverity.Error;
  end
  else if not ASucceeded then
  begin
    // Fehlgeschlagen ohne lesbare Fehlermeldung (z. B. Linker, abgebrochen).
    Result.Kind := TAtlasBuildNoticeKind.Failed;
    Result.Severity := TAtlasNotificationSeverity.Error;
  end
  else if Result.Warnings > 0 then
  begin
    Result.Kind := TAtlasBuildNoticeKind.Warnings;
    Result.Severity := TAtlasNotificationSeverity.Warning;
  end
  else
    Result.Kind := TAtlasBuildNoticeKind.Succeeded;
end;

class function TAtlasBuildNotices.FromVerdict(const AMessages: TArray<TAtlasCompilerMessage>;
  const AVerdict: TAtlasBuildVerdict): TAtlasBuildNotice;
begin
  Result := Default(TAtlasBuildNotice);
  Result.Errors := AVerdict.Errors;
  Result.Warnings := AVerdict.Warnings;
  Result.Hints := AVerdict.Hints;
  Result.Baselined := AVerdict.Baselined;
  Result.Reason := AVerdict.Reason;
  Result.PromotedCode := AVerdict.PromotedCode;
  Result.HasTarget := (AVerdict.First >= 0) and (AVerdict.First <= High(AMessages));
  if Result.HasTarget then
    Result.Target := AMessages[AVerdict.First];
  case AVerdict.Reason of
    TAtlasBuildVerdictReason.CompilerFailed:
      begin
        Result.Severity := TAtlasNotificationSeverity.Error;
        if Result.Errors > 0 then
          Result.Kind := TAtlasBuildNoticeKind.Errors
        else
          Result.Kind := TAtlasBuildNoticeKind.Failed;
      end;
    TAtlasBuildVerdictReason.WarningsAsErrors, TAtlasBuildVerdictReason.ZeroHints:
      begin
        Result.Severity := TAtlasNotificationSeverity.Error;
        Result.Kind := TAtlasBuildNoticeKind.Rejected;
      end;
  else
    if Result.Warnings > 0 then
    begin
      Result.Kind := TAtlasBuildNoticeKind.Warnings;
      Result.Severity := TAtlasNotificationSeverity.Warning;
    end
    else
    begin
      Result.Kind := TAtlasBuildNoticeKind.Succeeded;
      Result.Severity := TAtlasNotificationSeverity.Info;
    end;
  end;
end;

end.
