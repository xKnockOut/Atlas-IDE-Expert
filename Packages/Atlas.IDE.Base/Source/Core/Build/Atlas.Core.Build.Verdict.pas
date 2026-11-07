unit Atlas.Core.Build.Verdict;

// Schranke für Hinweise und Warnungen (#530), ohne VCL und Open Tools API:
// die eine Bewertung eines Builds aus seinen Compilermeldungen (#528). Die
// IDE meldet einen Build mit Warnungen und Hinweisen als erfolgreich; Atlas
// zählt nach und kann ihn als gescheitert werten (0/0/0-Regel):
// - Zählung: Fehler, Warnungen und Hinweise; Meldungen in der Basislinie
//   (#97, atlas-baseline.json) zählen nicht, sondern nur als "Baselined".
// - build.warningsAsErrors: Codes (W…, H…), die als Fehler zählen.
// - build.zeroHints: jede gezählte Warnung und jeder Hinweis lässt den Build
//   scheitern.
// Zusammenfassung, Eintrag der Benachrichtigungszentrale und Tests nach dem
// Build (#69) richten sich alle nach dieser Bewertung (Effective); Module
// hören über IAtlasBuildVerdictListener darauf (#1455).
//
// Welche Meldungen in der Basislinie stehen, weiß der Server
// (atlas.classifyCompilerMessages, Atlas.Common.Lsp.CompilerBaseline). Run
// fragt ihn über AClassify und bewertet ohne Server oder bei Fehler mit allen
// Meldungen. In die Basislinie übernimmt atlas.baselineCompilerMessages.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages;

type
  /// <summary>Warum der Build nicht als erfolgreich gilt; None = erfolgreich.</summary>
  TAtlasBuildVerdictReason = (None, CompilerFailed, WarningsAsErrors, ZeroHints);

  TAtlasBuildVerdictSettings = record
    /// <summary>build.zeroHints.</summary>
    ZeroHints: Boolean;
    /// <summary>build.warningsAsErrors, groß geschrieben (ParseCodes).</summary>
    WarningsAsErrors: TArray<string>;
    class function Create(AZeroHints: Boolean; const AWarningsAsErrors: string): TAtlasBuildVerdictSettings; static;
  end;

  TAtlasBuildVerdict = record
    /// <summary>Ergebnis des Compilers.</summary>
    Succeeded: Boolean;
    /// <summary>Gezählte Meldungen (ohne Basislinie).</summary>
    Errors: Integer;
    Warnings: Integer;
    Hints: Integer;
    /// <summary>Warnungen und Hinweise in der Basislinie, nicht gezählt.</summary>
    Baselined: Integer;
    /// <summary>Gezählte Warnungen und Hinweise aus build.warningsAsErrors.</summary>
    Promoted: Integer;
    /// <summary>Erster Code aus build.warningsAsErrors unter den Meldungen; '' ohne.</summary>
    PromotedCode: string;
    /// <summary>Basislinie befragt (Server antwortete)?</summary>
    BaselineChecked: Boolean;
    Reason: TAtlasBuildVerdictReason;
    /// <summary>Position der ersten maßgeblichen Meldung (Fehler, sonst Code aus warningsAsErrors, sonst erste
    /// gezählte Warnung bzw. Hinweis) mit Datei; -1 ohne.</summary>
    First: Integer;
    /// <summary>Gilt der Build als erfolgreich?</summary>
    function Effective: Boolean;
  end;

  /// <summary>Je Meldung: steht sie in der Basislinie? nil = keine Antwort.</summary>
  TAtlasBuildBaselined = reference to procedure(const ABaselined: TArray<Boolean>);
  /// <summary>Fragt die Basislinie im Hintergrund; ADone im Hauptthread (nil bei Fehler). False = nicht gefragt
  /// (kein Server), dann ruft der Aufrufer ADone nicht.</summary>
  TAtlasBuildClassify = reference to function(const AMessages: TArray<TAtlasCompilerMessage>;
    const ADone: TAtlasBuildBaselined): Boolean;
  TAtlasBuildVerdictDone = reference to procedure(const AVerdict: TAtlasBuildVerdict);

  /// <summary>Hört auf bewertete Builds des Benutzers (#530); Module stellen ihn über ihren Scope bereit (#1455),
  /// etwa die Tests nach dem Build (#69). Hauptthread, nach Zusammenfassung und Benachrichtigung.</summary>
  IAtlasBuildVerdictListener = interface
    ['{5F6C837F-1473-4EC8-B2F9-1A81BF8A7DAD}']
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

  TAtlasBuildVerdicts = class
  public const
    cClassifyCommand = 'atlas.classifyCompilerMessages';
    cAddCommand = 'atlas.baselineCompilerMessages';
    /// <summary>Zeitlimit der Frage nach der Basislinie; danach zählt alles.</summary>
    cClassifyTimeoutMs = 5000;
    cAddTimeoutMs = 30000;
  private type
    /// <summary>Erste Meldungen mit Datei je Art; -1 ohne.</summary>
    TFirsts = record
      Error: Integer;
      Promoted: Integer;
      Counted: Integer;
    end;
  private
    /// <summary>AIndex als AFirst merken, wenn noch keine Meldung mit Datei gemerkt ist.</summary>
    class procedure Remember(var AFirst: Integer; AIndex: Integer; const AMessage: TAtlasCompilerMessage); static;
    /// <summary>Zählt eine Warnung bzw. einen Hinweis außerhalb der Basislinie.</summary>
    class procedure CountCounted(var AVerdict: TAtlasBuildVerdict; var AFirsts: TFirsts; AIndex: Integer;
      const AMessage: TAtlasCompilerMessage; const ASettings: TAtlasBuildVerdictSettings); static;
    /// <summary>Grund aus den Zählern; None = erfolgreich.</summary>
    class function ReasonOf(const AVerdict: TAtlasBuildVerdict;
      const ASettings: TAtlasBuildVerdictSettings): TAtlasBuildVerdictReason; static;
  public
    /// <summary>Codes aus einer Liste wie "W1035, h2164; W1036": groß, ohne Doppelte, nur gültige Codes von
    /// Warnungen und Hinweisen (Buchstabe W oder H, vier Ziffern).</summary>
    class function ParseCodes(const AText: string): TArray<string>; static;
    /// <summary>Codes wie ParseCodes, mit ", " verbunden (gespeicherte Form).</summary>
    class function NormalizeCodes(const AText: string): string; static;
    /// <summary>Kann die Meldung in die Basislinie (Warnung oder Hinweis mit Code und Datei)?</summary>
    class function Baselinable(const AMessage: TAtlasCompilerMessage): Boolean; static;
    /// <summary>Gibt es Meldungen für die Basislinie?</summary>
    class function AnyBaselinable(const AMessages: TArray<TAtlasCompilerMessage>): Boolean; static;
    /// <summary>Bewertung; ABaselined parallel zu AMessages (kürzer oder nil = nicht in der Basislinie).
    /// </summary>
    class function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const ABaselined: TArray<Boolean>;
      ASucceeded: Boolean; const ASettings: TAtlasBuildVerdictSettings): TAtlasBuildVerdict; static;
    /// <summary>Bewertet, nach der Antwort von AClassify (nil = ohne Basislinie), und ruft ADone genau einmal.
    /// </summary>
    class procedure Run(const AMessages: TArray<TAtlasCompilerMessage>; ASucceeded: Boolean;
      const ASettings: TAtlasBuildVerdictSettings; const AClassify: TAtlasBuildClassify;
      const ADone: TAtlasBuildVerdictDone); static;
    /// <summary>Argumente (JSON-Array) für ClassifyCommand bzw. AddCommand: Projekt-URI und alle Meldungen.
    /// </summary>
    class function Arguments(const AProjectUri: string; const AMessages: TArray<TAtlasCompilerMessage>): string;
      static;
    /// <summary>Antwort von ClassifyCommand für ACount Meldungen; nil, wenn sie unbrauchbar ist.</summary>
    class function BaselinedOf(const AAnswer: TJSONValue; ACount: Integer): TArray<Boolean>; static;
  end;

  /// <summary>Antwort von AddCommand.</summary>
  TAtlasCompilerBaselineAdd = record
    FileName: string;
    Total: Integer;
    Files: Integer;
    Added: Integer;
    Removed: Integer;
    Unchanged: Integer;
    Skipped: Integer;
    /// <summary>False, wenn die Antwort unbrauchbar ist.</summary>
    class function FromServer(const AAnswer: TJSONValue; out AResult: TAtlasCompilerBaselineAdd): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections;

{ TAtlasBuildVerdictSettings }

class function TAtlasBuildVerdictSettings.Create(AZeroHints: Boolean;
  const AWarningsAsErrors: string): TAtlasBuildVerdictSettings;
begin
  Result.ZeroHints := AZeroHints;
  Result.WarningsAsErrors := TAtlasBuildVerdicts.ParseCodes(AWarningsAsErrors);
end;

{ TAtlasBuildVerdict }

function TAtlasBuildVerdict.Effective: Boolean;
begin
  Result := Reason = TAtlasBuildVerdictReason.None;
end;

{ TAtlasBuildVerdicts }

function IsWarningOrHintCode(const ACode: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (Length(ACode) = 5) and CharInSet(ACode[1], ['W', 'H']);
  if Result then
  begin
    for mIndex := 2 to 5 do
    begin
      if not CharInSet(ACode[mIndex], ['0'..'9']) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

class function TAtlasBuildVerdicts.ParseCodes(const AText: string): TArray<string>;
var
  mPart, mCode: string;
begin
  Result := nil;
  for mPart in UpperCase(AText).Split([',', ';', ' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty) do
  begin
    mCode := Trim(mPart);
    if IsWarningOrHintCode(mCode) and (IndexText(mCode, Result) < 0) then
    begin
      Result := Result + [mCode];
    end;
  end;
end;

class function TAtlasBuildVerdicts.NormalizeCodes(const AText: string): string;
begin
  Result := string.Join(', ', ParseCodes(AText));
end;

class function TAtlasBuildVerdicts.Baselinable(const AMessage: TAtlasCompilerMessage): Boolean;
begin
  Result := ((AMessage.Severity = TAtlasCompilerSeverity.Warning) or
    (AMessage.Severity = TAtlasCompilerSeverity.Hint)) and (AMessage.FileName <> '') and
    IsWarningOrHintCode(UpperCase(AMessage.Code));
end;

class function TAtlasBuildVerdicts.AnyBaselinable(const AMessages: TArray<TAtlasCompilerMessage>): Boolean;
var
  mMessage: TAtlasCompilerMessage;
begin
  Result := False;
  for mMessage in AMessages do
  begin
    if Baselinable(mMessage) then
    begin
      Exit(True);
    end;
  end;
end;

class procedure TAtlasBuildVerdicts.Remember(var AFirst: Integer; AIndex: Integer;
  const AMessage: TAtlasCompilerMessage);
begin
  if (AFirst < 0) and (AMessage.FileName <> '') then
  begin
    AFirst := AIndex;
  end;
end;

class procedure TAtlasBuildVerdicts.CountCounted(var AVerdict: TAtlasBuildVerdict; var AFirsts: TFirsts;
  AIndex: Integer; const AMessage: TAtlasCompilerMessage; const ASettings: TAtlasBuildVerdictSettings);
begin
  if AMessage.Severity = TAtlasCompilerSeverity.Warning then
  begin
    Inc(AVerdict.Warnings);
  end
  else
  begin
    Inc(AVerdict.Hints);
  end;
  Remember(AFirsts.Counted, AIndex, AMessage);
  if IndexText(AMessage.Code, ASettings.WarningsAsErrors) < 0 then
  begin
    Exit;
  end;
  Inc(AVerdict.Promoted);
  if AVerdict.PromotedCode = '' then
  begin
    AVerdict.PromotedCode := UpperCase(AMessage.Code);
  end;
  Remember(AFirsts.Promoted, AIndex, AMessage);
end;

class function TAtlasBuildVerdicts.ReasonOf(const AVerdict: TAtlasBuildVerdict;
  const ASettings: TAtlasBuildVerdictSettings): TAtlasBuildVerdictReason;
begin
  if not AVerdict.Succeeded or (AVerdict.Errors > 0) then
  begin
    Result := TAtlasBuildVerdictReason.CompilerFailed;
  end
  else if AVerdict.Promoted > 0 then
  begin
    Result := TAtlasBuildVerdictReason.WarningsAsErrors;
  end
  else if ASettings.ZeroHints and (AVerdict.Warnings + AVerdict.Hints > 0) then
  begin
    Result := TAtlasBuildVerdictReason.ZeroHints;
  end
  else
  begin
    Result := TAtlasBuildVerdictReason.None;
  end;
end;

class function TAtlasBuildVerdicts.Evaluate(const AMessages: TArray<TAtlasCompilerMessage>;
  const ABaselined: TArray<Boolean>; ASucceeded: Boolean;
  const ASettings: TAtlasBuildVerdictSettings): TAtlasBuildVerdict;
var
  mIndex: Integer;
  mMessage: TAtlasCompilerMessage;
  mFirsts: TFirsts;
begin
  Result := Default(TAtlasBuildVerdict);
  Result.Succeeded := ASucceeded;
  Result.BaselineChecked := ABaselined <> nil;
  mFirsts.Error := -1;
  mFirsts.Promoted := -1;
  mFirsts.Counted := -1;
  for mIndex := 0 to High(AMessages) do
  begin
    mMessage := AMessages[mIndex];
    case mMessage.Severity of
      TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal:
        begin
          Inc(Result.Errors);
          Remember(mFirsts.Error, mIndex, mMessage);
        end;
      TAtlasCompilerSeverity.Warning, TAtlasCompilerSeverity.Hint:
        begin
          if (mIndex <= High(ABaselined)) and ABaselined[mIndex] and Baselinable(mMessage) then
          begin
            Inc(Result.Baselined);
          end
          else
          begin
            CountCounted(Result, mFirsts, mIndex, mMessage, ASettings);
          end;
        end;
      TAtlasCompilerSeverity.Info: ;
    end;
  end;
  Result.Reason := ReasonOf(Result, ASettings);
  Result.First := mFirsts.Error;
  if Result.First < 0 then
  begin
    Result.First := mFirsts.Promoted;
  end;
  if Result.First < 0 then
  begin
    Result.First := mFirsts.Counted;
  end;
end;

class procedure TAtlasBuildVerdicts.Run(const AMessages: TArray<TAtlasCompilerMessage>; ASucceeded: Boolean;
  const ASettings: TAtlasBuildVerdictSettings; const AClassify: TAtlasBuildClassify;
  const ADone: TAtlasBuildVerdictDone);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mSucceeded: Boolean;
  mSettings: TAtlasBuildVerdictSettings;
  mDone: TAtlasBuildVerdictDone;
begin
  mMessages := AMessages;
  mSucceeded := ASucceeded;
  mSettings := ASettings;
  mDone := ADone;
  // Nur fragen, wenn es etwas zu fragen gibt; ohne Server zählt alles.
  if Assigned(AClassify) and AnyBaselinable(mMessages) and AClassify(mMessages,
    procedure(const ABaselined: TArray<Boolean>)
    begin
      mDone(Evaluate(mMessages, ABaselined, mSucceeded, mSettings));
    end) then
  begin
    Exit;
  end;
  mDone(Evaluate(mMessages, nil, mSucceeded, mSettings));
end;

class function TAtlasBuildVerdicts.Arguments(const AProjectUri: string;
  const AMessages: TArray<TAtlasCompilerMessage>): string;
var
  mArguments, mItems: TJSONArray;
  mItem: TJSONObject;
  mMessage: TAtlasCompilerMessage;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(AProjectUri);
    mItems := TJSONArray.Create;
    mArguments.AddElement(mItems);
    // Alle Meldungen: Die Positionen der Antwort gelten für AMessages; der Server übergeht die übrigen.
    for mMessage in AMessages do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('file', mMessage.FileName);
      mItem.AddPair('line', TJSONNumber.Create(mMessage.Line));
      mItem.AddPair('code', UpperCase(mMessage.Code));
      mItems.AddElement(mItem);
    end;
    Result := mArguments.ToJSON;
  finally
    mArguments.Free;
  end;
end;

class function TAtlasBuildVerdicts.BaselinedOf(const AAnswer: TJSONValue; ACount: Integer): TArray<Boolean>;
var
  mValue, mItem: TJSONValue;
  mIndex: Integer;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) then
  begin
    Exit;
  end;
  mValue := TJSONObject(AAnswer).GetValue('baselined');
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := False;
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if mItem is TJSONNumber then
    begin
      mIndex := TJSONNumber(mItem).AsInt;
      if (mIndex >= 0) and (mIndex < ACount) then
      begin
        Result[mIndex] := True;
      end;
    end;
  end;
end;

{ TAtlasCompilerBaselineAdd }

class function TAtlasCompilerBaselineAdd.FromServer(const AAnswer: TJSONValue;
  out AResult: TAtlasCompilerBaselineAdd): Boolean;
var
  mAnswer: TJSONObject;
begin
  AResult := Default(TAtlasCompilerBaselineAdd);
  Result := (AAnswer is TJSONObject) and (TJSONObject(AAnswer).GetValue('file') is TJSONString);
  if not Result then
  begin
    Exit;
  end;
  mAnswer := TJSONObject(AAnswer);
  AResult.FileName := mAnswer.GetValue('file').Value;
  AResult.Total := mAnswer.GetValue<Integer>('total', 0);
  AResult.Files := mAnswer.GetValue<Integer>('files', 0);
  AResult.Added := mAnswer.GetValue<Integer>('added', 0);
  AResult.Removed := mAnswer.GetValue<Integer>('removed', 0);
  AResult.Unchanged := mAnswer.GetValue<Integer>('unchanged', 0);
  AResult.Skipped := mAnswer.GetValue<Integer>('skipped', 0);
end;

end.
