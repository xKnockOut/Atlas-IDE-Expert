unit Atlas.Common.Mcp.IdeInbox;

// Austausch des MCP-Servers mit dem IDE-Plugin über einen Auftragsordner, gemeinsam für Builds
// (Atlas.Common.Mcp.IdeBuilds, #261) und Debuggen (Atlas.Common.Mcp.IdeDebug, #1874):
//   <Eingang>\<id>.json          Auftrag (erst als .tmp geschrieben, dann umbenannt)
//   <id>.taken                   das Plugin hat übernommen (Umbenennen ist der Zuschlag)
//   <id>.result.json             Antwort des Plugins
// Nimmt das Plugin den Auftrag nicht binnen TakeMs an, zieht der Server ihn zurück; antwortet es nach der Übernahme
// nicht binnen AnswerMs, gilt der Auftrag als abgelaufen. Was im Auftrag und in der Antwort steht, regeln die
// Aufrufer. Gegenstück im Plugin: TAtlasFileInbox (Atlas.Core.Assistants.Inbox).

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TMcpIdeExchangeOutcome = (Answered, NotTaken, TimedOut);

  /// <summary>Warten auf das Plugin: Wait schläft kurz (Tests übernehmen darin die Rolle des Plugins), Clock liefert
  /// Millisekunden, dazu die Fristen bis zur Übernahme und für die Antwort danach.</summary>
  TMcpIdeWaiting = record
    Wait: TProc;
    Clock: TFunc<Int64>;
    TakeMs: Int64;
    AnswerMs: Int64;
    class function Make(const AWait: TProc; const AClock: TFunc<Int64>; ATakeMs, AAnswerMs: Int64):
      TMcpIdeWaiting; static;
  end;

  TMcpIdeInbox = class
  public
    /// <summary>Legt ARequestText als Auftrag in AInbox und wartet auf das Plugin. Answered: AAnswerText ist die
    /// gelesene Antwort ('' wenn unlesbar); die Antwortdatei ist danach gelöscht.</summary>
    class function Exchange(const AInbox, ARequestText: string; const AWaiting: TMcpIdeWaiting;
      out AAnswerText: string): TMcpIdeExchangeOutcome; static;
  end;

implementation

uses
  System.IOUtils;

procedure DeleteQuietly(const AFileName: string);
begin
  try
    if FileExists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- Austauschdatei mit der IDE nach Kräften
    on Exception do
      ;
  end;
end;

{ TMcpIdeWaiting }

class function TMcpIdeWaiting.Make(const AWait: TProc; const AClock: TFunc<Int64>; ATakeMs,
  AAnswerMs: Int64): TMcpIdeWaiting;
begin
  Result.Wait := AWait;
  Result.Clock := AClock;
  Result.TakeMs := ATakeMs;
  Result.AnswerMs := AAnswerMs;
end;

{ TMcpIdeInbox }

class function TMcpIdeInbox.Exchange(const AInbox, ARequestText: string; const AWaiting: TMcpIdeWaiting;
  out AAnswerText: string): TMcpIdeExchangeOutcome;
var
  mId, mRequest, mAnswer: string;
  mStarted: Int64;
begin
  AAnswerText := '';
  mId := TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '');
  mRequest := TPath.Combine(AInbox, mId + '.json');
  mAnswer := TPath.Combine(AInbox, mId + '.result.json');
  ForceDirectories(AInbox);
  TFile.WriteAllText(mRequest + '.tmp', ARequestText, TEncoding.UTF8);
  TFile.Move(mRequest + '.tmp', mRequest);
  mStarted := AWaiting.Clock();
  // Warten, bis das Plugin den Auftrag übernimmt (die .json verschwindet) oder schon antwortet.
  while (AWaiting.Clock() - mStarted < AWaiting.TakeMs) and FileExists(mRequest) and not FileExists(mAnswer) do
  begin
    AWaiting.Wait();
  end;
  if FileExists(mRequest) and not FileExists(mAnswer) and DeleteFile(mRequest) then
  begin
    Exit(TMcpIdeExchangeOutcome.NotTaken);
  end;
  mStarted := AWaiting.Clock();
  while (AWaiting.Clock() - mStarted < AWaiting.AnswerMs) and not FileExists(mAnswer) do
  begin
    AWaiting.Wait();
  end;
  if not FileExists(mAnswer) then
  begin
    Exit(TMcpIdeExchangeOutcome.TimedOut);
  end;
  try
    AAnswerText := TFile.ReadAllText(mAnswer, TEncoding.UTF8);
  except
    // lsp-ignore: catch-all-without-raise -- Austauschdatei mit der IDE nach Kräften
    on Exception do
      AAnswerText := '';
  end;
  DeleteQuietly(mAnswer);
  Result := TMcpIdeExchangeOutcome.Answered;
end;

end.
