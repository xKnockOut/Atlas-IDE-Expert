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
// Build (#69) richten sich alle nach dieser Bewertung (Effective).
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

  TAtlasBuildVerdicts = class
  public const
    ClassifyCommand = 'atlas.classifyCompilerMessages';
    AddCommand = 'atlas.baselineCompilerMessages';
    /// <summary>Zeitlimit der Frage nach der Basislinie; danach zählt alles.</summary>
    ClassifyTimeoutMs = 5000;
    AddTimeoutMs = 30000;
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
  Index: Integer;
begin
  Result := (Length(ACode) = 5) and CharInSet(ACode[1], ['W', 'H']);
  if Result then
    for Index := 2 to 5 do
      if not CharInSet(ACode[Index], ['0'..'9']) then
        Exit(False);
end;

class function TAtlasBuildVerdicts.ParseCodes(const AText: string): TArray<string>;
var
  Part, Code: string;
begin
  Result := nil;
  for Part in UpperCase(AText).Split([',', ';', ' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty) do
  begin
    Code := Trim(Part);
    if IsWarningOrHintCode(Code) and (IndexText(Code, Result) < 0) then
      Result := Result + [Code];
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
  Message: TAtlasCompilerMessage;
begin
  Result := False;
  for Message in AMessages do
    if Baselinable(Message) then
      Exit(True);
end;

class function TAtlasBuildVerdicts.Evaluate(const AMessages: TArray<TAtlasCompilerMessage>;
  const ABaselined: TArray<Boolean>; ASucceeded: Boolean;
  const ASettings: TAtlasBuildVerdictSettings): TAtlasBuildVerdict;
var
  Index, FirstError, FirstPromoted, FirstCounted: Integer;
  Message: TAtlasCompilerMessage;
begin
  Result := Default(TAtlasBuildVerdict);
  Result.Succeeded := ASucceeded;
  Result.BaselineChecked := ABaselined <> nil;
  FirstError := -1;
  FirstPromoted := -1;
  FirstCounted := -1;
  for Index := 0 to High(AMessages) do
  begin
    Message := AMessages[Index];
    case Message.Severity of
      TAtlasCompilerSeverity.Error, TAtlasCompilerSeverity.Fatal:
        begin
          Inc(Result.Errors);
          if (FirstError < 0) and (Message.FileName <> '') then
            FirstError := Index;
        end;
      TAtlasCompilerSeverity.Warning, TAtlasCompilerSeverity.Hint:
        begin
          if (Index <= High(ABaselined)) and ABaselined[Index] and Baselinable(Message) then
          begin
            Inc(Result.Baselined);
            Continue;
          end;
          if Message.Severity = TAtlasCompilerSeverity.Warning then
            Inc(Result.Warnings)
          else
            Inc(Result.Hints);
          if (FirstCounted < 0) and (Message.FileName <> '') then
            FirstCounted := Index;
          if IndexText(Message.Code, ASettings.WarningsAsErrors) >= 0 then
          begin
            Inc(Result.Promoted);
            if Result.PromotedCode = '' then
              Result.PromotedCode := UpperCase(Message.Code);
            if (FirstPromoted < 0) and (Message.FileName <> '') then
              FirstPromoted := Index;
          end;
        end;
      TAtlasCompilerSeverity.Info: ;
    end;
  end;
  if not ASucceeded or (Result.Errors > 0) then
    Result.Reason := TAtlasBuildVerdictReason.CompilerFailed
  else if Result.Promoted > 0 then
    Result.Reason := TAtlasBuildVerdictReason.WarningsAsErrors
  else if ASettings.ZeroHints and (Result.Warnings + Result.Hints > 0) then
    Result.Reason := TAtlasBuildVerdictReason.ZeroHints
  else
    Result.Reason := TAtlasBuildVerdictReason.None;
  Result.First := FirstError;
  if Result.First < 0 then
    Result.First := FirstPromoted;
  if Result.First < 0 then
    Result.First := FirstCounted;
end;

class procedure TAtlasBuildVerdicts.Run(const AMessages: TArray<TAtlasCompilerMessage>; ASucceeded: Boolean;
  const ASettings: TAtlasBuildVerdictSettings; const AClassify: TAtlasBuildClassify;
  const ADone: TAtlasBuildVerdictDone);
var
  Messages: TArray<TAtlasCompilerMessage>;
  Succeeded: Boolean;
  Settings: TAtlasBuildVerdictSettings;
  Done: TAtlasBuildVerdictDone;
begin
  Messages := AMessages;
  Succeeded := ASucceeded;
  Settings := ASettings;
  Done := ADone;
  // Nur fragen, wenn es etwas zu fragen gibt; ohne Server zählt alles.
  if Assigned(AClassify) and AnyBaselinable(Messages) and AClassify(Messages,
    procedure(const ABaselined: TArray<Boolean>)
    begin
      Done(Evaluate(Messages, ABaselined, Succeeded, Settings));
    end) then
    Exit;
  Done(Evaluate(Messages, nil, Succeeded, Settings));
end;

class function TAtlasBuildVerdicts.Arguments(const AProjectUri: string;
  const AMessages: TArray<TAtlasCompilerMessage>): string;
var
  Arguments, Items: TJSONArray;
  Item: TJSONObject;
  Message: TAtlasCompilerMessage;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(AProjectUri);
    Items := TJSONArray.Create;
    Arguments.AddElement(Items);
    // Alle Meldungen: Die Positionen der Antwort gelten für AMessages; der Server übergeht die übrigen.
    for Message in AMessages do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('file', Message.FileName);
      Item.AddPair('line', TJSONNumber.Create(Message.Line));
      Item.AddPair('code', UpperCase(Message.Code));
      Items.AddElement(Item);
    end;
    Result := Arguments.ToJSON;
  finally
    Arguments.Free;
  end;
end;

class function TAtlasBuildVerdicts.BaselinedOf(const AAnswer: TJSONValue; ACount: Integer): TArray<Boolean>;
var
  Value, Item: TJSONValue;
  Index: Integer;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) then
    Exit;
  Value := TJSONObject(AAnswer).GetValue('baselined');
  if not (Value is TJSONArray) then
    Exit;
  SetLength(Result, ACount);
  for Index := 0 to ACount - 1 do
    Result[Index] := False;
  for Item in TJSONArray(Value) do
    if Item is TJSONNumber then
    begin
      Index := TJSONNumber(Item).AsInt;
      if (Index >= 0) and (Index < ACount) then
        Result[Index] := True;
    end;
end;

{ TAtlasCompilerBaselineAdd }

class function TAtlasCompilerBaselineAdd.FromServer(const AAnswer: TJSONValue;
  out AResult: TAtlasCompilerBaselineAdd): Boolean;
var
  Answer: TJSONObject;
begin
  AResult := Default(TAtlasCompilerBaselineAdd);
  Result := (AAnswer is TJSONObject) and (TJSONObject(AAnswer).GetValue('file') is TJSONString);
  if not Result then
    Exit;
  Answer := TJSONObject(AAnswer);
  AResult.FileName := Answer.GetValue('file').Value;
  AResult.Total := Answer.GetValue<Integer>('total', 0);
  AResult.Files := Answer.GetValue<Integer>('files', 0);
  AResult.Added := Answer.GetValue<Integer>('added', 0);
  AResult.Removed := Answer.GetValue<Integer>('removed', 0);
  AResult.Unchanged := Answer.GetValue<Integer>('unchanged', 0);
  AResult.Skipped := Answer.GetValue<Integer>('skipped', 0);
end;

end.
