unit Atlas.Core.Tracker.TestSupport;

// Gemeinsames der Tracker-Tests: Transporte mit festen Antworten (lesen und schreiben), Beispieldateien aus
// Tests\Data und Ziele für GitHub und YouTrack.

interface

uses
  Atlas.Core.Ci.Contract,
  Atlas.Plugin.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Contract.MyIssues;

type
  /// <summary>Transport ohne Inhalte: jede Leseanfrage endet mit Status 404.</summary>
  TNotFoundTransport = class(TInterfacedObject, IAtlasCiTransport)
  public
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Transport mit festen Antworten je Adressanfang; zählt die Aufrufe.</summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    FFail: TAtlasCiFetchError;
  public
    Calls: TArray<string>;
    procedure Answer(const APrefix: string; AStatus: Integer; const AText: string);
    procedure FailWith(AError: TAtlasCiFetchError);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

  /// <summary>Transport, der auch schreibt (#1279): merkt sich Methoden, Adressen und Inhalte, Antworten je
  /// Adressanfang.</summary>
  TFakePostTransport = class(TFakeTransport, IAtlasCiSend)
  private
    FPostPrefixes: TArray<string>;
    FPostStatus: TArray<Integer>;
    FPostTexts: TArray<string>;
  public
    Methods: TArray<string>;
    Posts: TArray<string>;
    Bodies: TArray<string>;
    procedure AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

  /// <summary>
  ///   Transport, der liest und schreibt, mit festen Antworten je Methode und Adressanfang; merkt sich Aufrufe
  ///   ("GET https://…") und Inhalte. Ohne passende Antwort Status 404.
  /// </summary>
  TFakeMethodTransport = class(TInterfacedObject, IAtlasCiTransport, IAtlasCiSend)
  private
    FMethods: TArray<string>;
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    function Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
  public
    Calls: TArray<string>;
    Bodies: TArray<string>;
    destructor Destroy; override;
    procedure Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AResponse: TAtlasCiResponse):
      Boolean;
  end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
/// <summary>GitHub-Ziel beispiel/atlas auf github.com.</summary>
function GitHubTarget: TAtlasTrackerTarget;
/// <summary>YouTrack-Ziel ATL auf beispiel.youtrack.cloud.</summary>
function YouTrackTarget: TAtlasTrackerTarget;
/// <summary>Leeres Issue mit Schlüssel, Nummer und Titel.</summary>
function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;

/// <summary>Namen der Abfragen, je mit Semikolon abgeschlossen.</summary>
function QueryNames(const AQueries: TArray<TAtlasTrackerQuery>): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Tests.Files;

{ TNotFoundTransport }

function TNotFoundTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AStatus := 404;
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := True;
end;

{ TFakeTransport }

procedure TFakeTransport.Answer(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

procedure TFakeTransport.FailWith(AError: TAtlasCiFetchError);
begin
  FFail := AError;
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AStatus := 0;
  AText := '';
  AError := FFail;
  if FFail <> TAtlasCiFetchError.None then
  begin
    Exit(False);
  end;
  for mIndex := 0 to High(FPrefixes) do
  begin
    if Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex] then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit(True);
    end;
  end;
  AStatus := 404;
  Result := True;
end;

{ TFakePostTransport }

procedure TFakePostTransport.AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPostPrefixes := FPostPrefixes + [APrefix];
  FPostStatus := FPostStatus + [AStatus];
  FPostTexts := FPostTexts + [AText];
end;

function TFakePostTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
var
  mIndex: Integer;
begin
  Methods := Methods + [AMethod];
  Posts := Posts + [AUrl];
  Bodies := Bodies + [ABody];
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  AResponse.Status := 404;
  Result := True;
  for mIndex := 0 to High(FPostPrefixes) do
  begin
    if Copy(AUrl, 1, Length(FPostPrefixes[mIndex])) = FPostPrefixes[mIndex] then
    begin
      AResponse.Status := FPostStatus[mIndex];
      AResponse.Text := FPostTexts[mIndex];
      Exit;
    end;
  end;
end;

{ TFakeMethodTransport }

destructor TFakeMethodTransport.Destroy;
begin
  FMethods := nil;
  FPrefixes := nil;
  FStatus := nil;
  FTexts := nil;
  Calls := nil;
  Bodies := nil;
  inherited Destroy;
end;

function TFakeMethodTransport.Reply(const AMethod, AUrl: string; out AStatus: Integer; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AMethod + ' ' + AUrl];
  AStatus := 404;
  AText := '';
  Result := True;
  for mIndex := 0 to High(FPrefixes) do
  begin
    if (FMethods[mIndex] = AMethod) and AUrl.StartsWith(FPrefixes[mIndex]) then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit;
    end;
  end;
end;

procedure TFakeMethodTransport.Answer(const AMethod, APrefix: string; AStatus: Integer; const AText: string);
begin
  FMethods := FMethods + [AMethod];
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeMethodTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  AError := TAtlasCiFetchError.None;
  Result := Reply('GET', AUrl, AStatus, AText);
end;

function TFakeMethodTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer;
  out AResponse: TAtlasCiResponse): Boolean;
begin
  AResponse := TAtlasCiResponse.Failed(TAtlasCiFetchError.None);
  Bodies := Bodies + [ABody];
  Result := Reply(AMethod, AUrl, AResponse.Status, AResponse.Text);
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
begin
  Result := TTestData.Fixture(AFolder, AName);
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud/', 'ATL', '');
end;

function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

function QueryNames(const AQueries: TArray<TAtlasTrackerQuery>): string;
var
  mQuery: TAtlasTrackerQuery;
begin
  Result := '';
  for mQuery in AQueries do
  begin
    Result := Result + mQuery.Name + ';';
  end;
end;

end.
