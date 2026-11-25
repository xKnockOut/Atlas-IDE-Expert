unit Atlas.Tests.IssueLoaderFake;

// Fälschung für den Lader der Issue-Vorschau (TAtlasIssueLoader,
// Atlas.Core.Tracker.PreviewLoad): startet keine Abfrage, sondern schreibt
// mit, was der Ablauf verlangt („start:<Kennung>:<Generation>“, „cancel“,
// „ended“, „arrived:<Kennung>:<Schritt>“). Die Antworten gibt der Test selbst
// über TAtlasIssueLoadFlow.Finished. Mit Refuse startet keine Abfrage (kein
// Token).

interface

uses
  System.Classes,
  Atlas.Plugin.CiBuild.Contract,
  Atlas.Core.Tracker.Preview,
  Atlas.Core.Tracker.PreviewLoad;

type
  /// <summary>Lader, der seine Aufrufe als Text mitschreibt ("start:A:1", "cancel", "ended", "arrived:A:Show").
  /// </summary>
  TAtlasIssueLoaderFake = class
  private
    FCalls: TStringList;
    FGeneration: Integer;
    FRefuse: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Start(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer;
      out AError: TAtlasCiFetchError): Boolean;
    procedure Arrived(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
    procedure Note(const ACall: string);
    /// <summary>Lader für den Ablauf, der auf diese Fälschung zeigt.</summary>
    function Loader: TAtlasIssueLoader;
    /// <summary>Aufrufe mit Komma getrennt.</summary>
    function CallText: string;
    /// <summary>Generation des jüngsten Wunsches; Abmelden zählt sie wie die IDE hoch.</summary>
    property Generation: Integer read FGeneration write FGeneration;
    /// <summary>Start ohne Abfrage (kein Token).</summary>
    property Refuse: Boolean read FRefuse write FRefuse;
    property Calls: TStringList read FCalls;
  end;

/// <summary>Name des Schritts für die mitgeschriebenen Aufrufe.</summary>
function StepName(AStep: TAtlasIssueLoadStep): string;

implementation

uses
  System.SysUtils;

function StepName(AStep: TAtlasIssueLoadStep): string;
begin
  case AStep of
    TAtlasIssueLoadStep.Pending:
      Result := 'Pending';
    TAtlasIssueLoadStep.Outdated:
      Result := 'Outdated';
    TAtlasIssueLoadStep.Show:
      Result := 'Show';
  else
    Result := 'Fail';
  end;
end;

{ TAtlasIssueLoaderFake }

constructor TAtlasIssueLoaderFake.Create;
begin
  inherited Create;
  FCalls := TStringList.Create;
end;

destructor TAtlasIssueLoaderFake.Destroy;
begin
  FCalls.Free;
  inherited;
end;

procedure TAtlasIssueLoaderFake.Note(const ACall: string);
begin
  FCalls.Add(ACall);
end;

function TAtlasIssueLoaderFake.Start(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Inc(FGeneration);
  AGeneration := FGeneration;
  AError := TAtlasCiFetchError.Unauthorized;
  Result := not FRefuse;
  Note(Format('start:%s:%d', [AEntry.Key, AGeneration]));
end;

procedure TAtlasIssueLoaderFake.Arrived(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep);
begin
  Note('arrived:' + AAnswer.Entry.Key + ':' + StepName(AStep));
end;

function TAtlasIssueLoaderFake.Loader: TAtlasIssueLoader;
var
  mFake: TAtlasIssueLoaderFake;
begin
  mFake := Self;
  Result := Default(TAtlasIssueLoader);
  Result.Start :=
    function(const AEntry: TAtlasIssueHistoryEntry; out AGeneration: Integer; out AError: TAtlasCiFetchError): Boolean
    begin
      Result := mFake.Start(AEntry, AGeneration, AError);
    end;
  Result.Cancel :=
    procedure
    begin
      mFake.Note('cancel');
    end;
  Result.Ended :=
    procedure
    begin
      mFake.Note('ended');
    end;
  Result.Generation :=
    function: Integer
    begin
      Result := mFake.Generation;
    end;
  Result.Arrived :=
    procedure(const AAnswer: TAtlasIssueLoadAnswer; AStep: TAtlasIssueLoadStep)
    begin
      mFake.Arrived(AAnswer, AStep);
    end;
end;

function TAtlasIssueLoaderFake.CallText: string;
begin
  // Die Aufrufe enthalten weder Leerzeichen noch Kommas: CommaText setzt keine Anführungszeichen.
  Result := FCalls.CommaText;
end;

end.
