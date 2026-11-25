unit Atlas.IDE.Assistants.Adapters.TextSource;

// Quelle für einfache Aufgaben (#2744): Das Modul KI-Assistenten stellt anderen Modulen genau ein IAtlasAiText
// bereit; dahinter wählt diese Klasse bei jeder Anfrage zwischen dem eigenen Anbieter (#1922, #2056) und einem
// Anbieter der IDE (Smart CodeInsight) nach assistants.textSource:
// - ide: der Anbieter der IDE, wenn er bereit ist, sonst der eigene;
// - own: der eigene Anbieter, wenn er eingerichtet ist, sonst der Anbieter der IDE;
// - none: keine Quelle; die Verbraucher zeigen ihre KI-Funktion nicht.
// Dateien unter assistants.exclude gehen nie hinaus, gleich an welche Quelle (Failed mit Hinweis).
// Tickets der beiden Quellen bekommen eigene Nummern, damit Cancel die richtige trifft.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.IDE.Base.Foundation.AiText;

type
{$SCOPEDENUMS ON}
  /// <summary>Wer eine Anfrage übernimmt.</summary>
  TAtlasAiTextPick = (None, Own, Ide);
{$SCOPEDENUMS OFF}

  /// <summary>Einstellungen, bei jeder Anfrage neu gelesen.</summary>
  TAtlasAiTextSourceOptions = record
    /// <summary>assistants.textSource: ide, own oder none.</summary>
    Source: string;
    /// <summary>assistants.exclude</summary>
    Exclude: string;
  end;

  TAtlasAiTextSourceOptionsOf = reference to function: TAtlasAiTextSourceOptions;

  TAtlasAiTextSource = class(TInterfacedObject, IAtlasAiText)
  public const
    cIde = 'ide';
    cOwn = 'own';
    cNone = 'none';
  private type
    TRoute = record
      Service: IAtlasAiText;
      Ticket: Integer;
    end;
  private
    FOwn: IAtlasAiText;
    FIde: IAtlasAiText;
    FOptions: TAtlasAiTextSourceOptionsOf;
    FExcluded: string;
    FRoutes: TDictionary<Integer, TRoute>;
    FNext: Integer;
    function Chosen: IAtlasAiText;
    function Routed(ATicket: Integer; const ADone: TAtlasAiTextDone): TAtlasAiTextDone;
    procedure Forget(ATicket: Integer);
  public
    /// <summary>AOwn: eigener Anbieter; AIde: Anbieter der IDE; AExcluded: Fehlertext für ausgeschlossene Dateien.
    /// </summary>
    constructor Create(const AOwn, AIde: IAtlasAiText; const AOptions: TAtlasAiTextSourceOptionsOf;
      const AExcluded: string);
    destructor Destroy; override;
    /// <summary>Beide Quellen loslassen; danach nie mehr bereit. Offene Tickets meldet die jeweilige Quelle bei
    /// ihrem eigenen Stop.</summary>
    procedure Stop;
    function Ready: Boolean;
    function ProviderName: string;
    function Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
    procedure Cancel(ATicket: Integer);
    /// <summary>Wer übernimmt bei assistants.textSource = ASource und dem Stand der beiden Quellen.</summary>
    class function Choose(const ASource: string; AOwnReady, AIdeReady: Boolean): TAtlasAiTextPick; static;
  end;

implementation

uses
  Atlas.Core.Assistants.AiGhost;

{ TAtlasAiTextSource }

constructor TAtlasAiTextSource.Create(const AOwn, AIde: IAtlasAiText; const AOptions: TAtlasAiTextSourceOptionsOf;
  const AExcluded: string);
begin
  inherited Create;
  FOwn := AOwn;
  FIde := AIde;
  FOptions := AOptions;
  FExcluded := AExcluded;
  FRoutes := TDictionary<Integer, TRoute>.Create;
end;

destructor TAtlasAiTextSource.Destroy;
begin
  Stop;
  FreeAndNil(FRoutes);
  inherited Destroy;
end;

procedure TAtlasAiTextSource.Stop;
begin
  FOwn := nil;
  FIde := nil;
  FOptions := nil;
  if FRoutes <> nil then
  begin
    FRoutes.Clear;
  end;
end;

class function TAtlasAiTextSource.Choose(const ASource: string; AOwnReady, AIdeReady: Boolean): TAtlasAiTextPick;
begin
  Result := TAtlasAiTextPick.None;
  if SameText(ASource, cNone) then
  begin
    Exit;
  end;
  if SameText(ASource, cOwn) then
  begin
    if AOwnReady then
    begin
      Result := TAtlasAiTextPick.Own;
    end
    else if AIdeReady then
    begin
      Result := TAtlasAiTextPick.Ide;
    end;
    Exit;
  end;
  if AIdeReady then
  begin
    Result := TAtlasAiTextPick.Ide;
  end
  else if AOwnReady then
  begin
    Result := TAtlasAiTextPick.Own;
  end;
end;

function TAtlasAiTextSource.Chosen: IAtlasAiText;
var
  mOwnReady: Boolean;
  mIdeReady: Boolean;
begin
  Result := nil;
  if not Assigned(FOptions) then
  begin
    Exit;
  end;
  mOwnReady := (FOwn <> nil) and FOwn.Ready;
  mIdeReady := (FIde <> nil) and FIde.Ready;
  case Choose(FOptions().Source, mOwnReady, mIdeReady) of
    TAtlasAiTextPick.Own:
      Result := FOwn;
    TAtlasAiTextPick.Ide:
      Result := FIde;
  else
    Result := nil;
  end;
end;

function TAtlasAiTextSource.Ready: Boolean;
begin
  Result := Chosen <> nil;
end;

function TAtlasAiTextSource.ProviderName: string;
var
  mService: IAtlasAiText;
begin
  Result := '';
  mService := Chosen;
  if mService <> nil then
  begin
    Result := mService.ProviderName;
  end;
end;

procedure TAtlasAiTextSource.Forget(ATicket: Integer);
begin
  if FRoutes <> nil then
  begin
    FRoutes.Remove(ATicket);
  end;
end;

function TAtlasAiTextSource.Routed(ATicket: Integer; const ADone: TAtlasAiTextDone): TAtlasAiTextDone;
var
  mSelf: TAtlasAiTextSource;
begin
  mSelf := Self;
  Result :=
    procedure(const AResult: TAtlasAiTextResult)
    begin
      mSelf.Forget(ATicket);
      ADone(AResult);
    end;
end;

function TAtlasAiTextSource.Ask(const ARequest: TAtlasAiTextRequest; const ADone: TAtlasAiTextDone): Integer;
var
  mService: IAtlasAiText;
  mResult: TAtlasAiTextResult;
  mRoute: TRoute;
begin
  Result := 0;
  mService := Chosen;
  if mService = nil then
  begin
    mResult := Default(TAtlasAiTextResult);
    mResult.Status := TAtlasAiTextStatus.NotReady;
    ADone(mResult);
    Exit;
  end;
  if (ARequest.FileName <> '') and TAtlasAiGhost.Excluded(ARequest.FileName, FOptions().Exclude) then
  begin
    mResult := Default(TAtlasAiTextResult);
    mResult.Status := TAtlasAiTextStatus.Failed;
    mResult.Error := FExcluded;
    ADone(mResult);
    Exit;
  end;
  Inc(FNext);
  mRoute.Service := mService;
  mRoute.Ticket := mService.Ask(ARequest, Routed(FNext, ADone));
  if mRoute.Ticket > 0 then
  begin
    FRoutes.AddOrSetValue(FNext, mRoute);
    Result := FNext;
  end;
end;

procedure TAtlasAiTextSource.Cancel(ATicket: Integer);
var
  mRoute: TRoute;
begin
  if (FRoutes <> nil) and FRoutes.TryGetValue(ATicket, mRoute) then
  begin
    FRoutes.Remove(ATicket);
    mRoute.Service.Cancel(mRoute.Ticket);
  end;
end;

end.
