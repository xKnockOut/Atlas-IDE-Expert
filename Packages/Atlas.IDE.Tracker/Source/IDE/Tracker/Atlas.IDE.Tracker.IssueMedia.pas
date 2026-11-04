unit Atlas.IDE.Tracker.IssueMedia;

// Bilder und Anhänge im Fenster „Atlas-Issue“ (#1264):
// - Bilder: nur vom Server des Tokens (TAtlasIssuePreview.MayLoad), im
//   Hintergrund über IAtlasCiDownload, höchstens MaxImages je Issue.
// - Anhänge: Doppelklick lädt nach %TEMP%\Atlas\issues\<Kennung>\ und öffnet
//   mit dem zugeordneten Programm; ausführbare Dateien zeigt Atlas nur im
//   Explorer. Dateien anderer Server (GitHub) öffnen im Browser.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.IDE.Tracker.IssueContext;

type
  TAtlasIdeIssueMedia = class
  public const
    MaxImages = 10;
  private
    FContext: TAtlasIdeIssueContext;
    FThread: TThread;
    FCancel: IAtlasCiCancel;
  public
    constructor Create(AContext: TAtlasIdeIssueContext);
    /// <summary>Bilder zu AUrls des gezeigten Issues laden (nach ShowDetails).</summary>
    procedure LoadImages(const AUrls: TArray<string>);
    /// <summary>Anhang laden und öffnen bzw. im Browser zeigen.</summary>
    procedure OpenAttachment(const AAttachment: TAtlasTrackerAttachment);
    /// <summary>Laufendes Laden der Bilder abbrechen.</summary>
    procedure Cancel;
    /// <summary>Thread der Bilder dem Kontext zum Aufräumen geben.</summary>
    procedure Retire;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  System.IOUtils,
  System.StrUtils,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Core.Tracker.Preview,
  Atlas.UI.Tracker.IssueFrame,
  Atlas.UI.Tracker.Strings;

/// <summary>Höchstens MaxImages Adressen vom Server des Tokens, ohne Doppelte.</summary>
function LoadableUrls(const AUrls: TArray<string>; const AServer: string): TArray<string>;
var
  mUrl: string;
begin
  Result := nil;
  for mUrl in AUrls do
  begin
    if TAtlasIssuePreview.MayLoad(mUrl, AServer) and (Length(Result) < TAtlasIdeIssueMedia.MaxImages) and
      (IndexText(mUrl, Result) < 0) then
    begin
      Result := Result + [mUrl];
    end;
  end;
end;

procedure ImageLoaded(AOwner: TAtlasIdeIssueMedia; AGeneration: Integer; const AUrl: string; const ABytes: TBytes);
var
  mFrame: TAtlasIssueFrame;
  mStream: TBytesStream;
  mImage: TWICImage;
begin
  mFrame := AOwner.FContext.Frame;
  if not AOwner.FContext.Started or (AGeneration <> AOwner.FContext.Generation) or (Length(ABytes) = 0) or
    (mFrame = nil) then
  begin
    Exit;
  end;
  // PNG, JPEG, GIF, BMP und TIFF über WIC; Unlesbares bleibt ein Link.
  mImage := TWICImage.Create;
  mStream := TBytesStream.Create(ABytes);
  try
    try
      mImage.LoadFromStream(mStream);
    except
      on Exception do
        FreeAndNil(mImage);
    end;
  finally
    mStream.Free;
  end;
  if mImage <> nil then
  begin
    mFrame.SetImage(AUrl, mImage);
  end;
end;

/// <summary>Ein Bild laden; False = abgebrochen (keine weiteren).</summary>
function DownloadImage(const ADownload: IAtlasCiDownload; const AUrl: string; out ABytes: TBytes): Boolean;
var
  mStatus: Integer;
  mError: TAtlasCiFetchError;
begin
  Result := True;
  ABytes := nil;
  try
    if not ADownload.GetBytes(AUrl, TAtlasIssuePreview.TimeoutMs, TAtlasIssuePreview.MaxImageBytes, mStatus, ABytes,
      mError) then
    begin
      Result := mError <> TAtlasCiFetchError.Cancelled;
      ABytes := nil;
    end
    else if mStatus <> 200 then
    begin
      ABytes := nil;
    end;
  except
    on Exception do
      ABytes := nil;
  end;
end;

/// <summary>Geladenes Bild im Hauptthread an den Frame; eigene Routine je Bild.</summary>
procedure QueueImage(AOwner: TAtlasIdeIssueMedia; const AKeep: IInterface; AGeneration: Integer; const AUrl: string;
  const ABytes: TBytes);
var
  mKeep: IInterface;
begin
  mKeep := AKeep;
  TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
    procedure
    begin
      if mKeep <> nil then
      begin
        ImageLoaded(AOwner, AGeneration, AUrl, ABytes);
      end;
    end);
end;

procedure StartImages(AOwner: TAtlasIdeIssueMedia; const AUrls: TArray<string>; const ADownload: IAtlasCiDownload);
var
  mKeep: IInterface;
  mDownload: IAtlasCiDownload;
  mGeneration: Integer;
begin
  mKeep := AOwner.FContext.Keep;
  mDownload := ADownload;
  mGeneration := AOwner.FContext.Generation;
  AOwner.FThread := TThread.CreateAnonymousThread(
    procedure
    var
      mUrl: string;
      mBytes: TBytes;
    begin
      for mUrl in AUrls do
      begin
        if TAtlasShutdown.Signalled or not DownloadImage(mDownload, mUrl, mBytes) then
        begin
          Exit;
        end;
        if mBytes <> nil then
        begin
          QueueImage(AOwner, mKeep, mGeneration, mUrl, mBytes);
        end;
      end;
      mDownload := nil;
    end);
  AOwner.FThread.FreeOnTerminate := False;
  AOwner.FThread.Start;
end;

procedure AttachmentLoaded(AOwner: TAtlasIdeIssueMedia; const AFileName: string; ASucceeded: Boolean;
  const AName: string);
var
  mFrame: TAtlasIssueFrame;
begin
  AOwner.FContext.ReleaseThreads(False);
  if not AOwner.FContext.Started then
  begin
    Exit;
  end;
  if ASucceeded then
  begin
    // Ausführbares nie starten: im Explorer zeigen.
    TAtlasIssuePreview.OpenDownloaded(AFileName);
    Exit;
  end;
  mFrame := AOwner.FContext.Frame;
  if mFrame <> nil then
  begin
    mFrame.ShowError(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssuePreviewAttachmentFailed, [AName]),
      TAtlasIssueFix.None);
  end;
end;

/// <summary>Anhang im Hintergrund nach AFile laden; danach AttachmentLoaded im Hauptthread.</summary>
procedure StartAttachment(AOwner: TAtlasIdeIssueMedia; const ADownload: IAtlasCiDownload; const AUrl, AFile,
  AName: string);
var
  mKeep: IInterface;
  mDownload: IAtlasCiDownload;
begin
  mKeep := AOwner.FContext.Keep;
  mDownload := ADownload;
  AOwner.FContext.Run(TThread.CreateAnonymousThread(
    procedure
    var
      mStatus: Integer;
      mBytes: TBytes;
      mError: TAtlasCiFetchError;
      mOk: Boolean;
    begin
      mOk := False;
      try
        if mDownload.GetBytes(AUrl, TAtlasIssuePreview.TimeoutMs * 3, TAtlasIssuePreview.MaxAttachmentBytes,
          mStatus, mBytes, mError) and (mStatus = 200) then
        begin
          ForceDirectories(ExtractFileDir(AFile));
          TFile.WriteAllBytes(AFile, mBytes);
          mOk := True;
        end;
      except
        on Exception do
          mOk := False;
      end;
      mDownload := nil;
      if TAtlasShutdown.Signalled then
      begin
        Exit;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.WelcomePage,
        procedure
        begin
          if mKeep <> nil then
          begin
            AttachmentLoaded(AOwner, AFile, mOk, AName);
          end;
        end);
    end));
end;

{ TAtlasIdeIssueMedia }

constructor TAtlasIdeIssueMedia.Create(AContext: TAtlasIdeIssueContext);
begin
  inherited Create;
  FContext := AContext;
end;

procedure TAtlasIdeIssueMedia.Cancel;
begin
  if FCancel <> nil then
  begin
    FCancel.Cancel;
  end;
end;

procedure TAtlasIdeIssueMedia.Retire;
begin
  FContext.Retire(FThread);
  FThread := nil;
end;

procedure TAtlasIdeIssueMedia.LoadImages(const AUrls: TArray<string>);
var
  mProvider: IAtlasTrackerProvider;
  mTransport: IAtlasCiTransport;
  mDownload: IAtlasCiDownload;
  mUrls: TArray<string>;
begin
  if not FContext.Started or not FContext.HasCurrent or not FContext.CanTransport then
  begin
    Exit;
  end;
  Cancel;
  Retire;
  FContext.ReleaseThreads(False);
  mProvider := FContext.ProviderOf(FContext.Current.Target);
  if mProvider = nil then
  begin
    Exit;
  end;
  // Nur Bilder vom Server, an den das Token geht; alles andere bleibt ein Link.
  mUrls := LoadableUrls(AUrls, mProvider.ApiServer(FContext.Current.Target));
  if Length(mUrls) = 0 then
  begin
    Exit;
  end;
  mTransport := FContext.TransportOf(mProvider, FContext.Current.Target);
  if Supports(mTransport, IAtlasCiDownload, mDownload) then
  begin
    if not Supports(mTransport, IAtlasCiCancel, FCancel) then
    begin
      FCancel := nil;
    end;
    StartImages(Self, mUrls, mDownload);
  end;
end;

procedure TAtlasIdeIssueMedia.OpenAttachment(const AAttachment: TAtlasTrackerAttachment);
var
  mProvider: IAtlasTrackerProvider;
  mDownload: IAtlasCiDownload;
  mFolder, mUrl: string;
begin
  mProvider := nil;
  if FContext.Started and FContext.HasCurrent then
  begin
    mProvider := FContext.ProviderOf(FContext.Current.Target);
  end;
  if mProvider = nil then
  begin
    Exit;
  end;
  mUrl := AAttachment.Url;
  // Dateien anderer Server (GitHub) bzw. ohne Token: im Browser.
  if AAttachment.External or not TAtlasIssuePreview.MayLoad(mUrl, mProvider.ApiServer(FContext.Current.Target)) or
    not FContext.CanTransport then
  begin
    TAtlasIssuePreview.Browse(mUrl);
    Exit;
  end;
  if Supports(FContext.TransportOf(mProvider, FContext.Current.Target), IAtlasCiDownload, mDownload) then
  begin
    mFolder := TPath.Combine(TPath.Combine(TPath.Combine(TPath.GetTempPath, 'Atlas'), 'issues'),
      TAtlasTrackerIssueCache.SafeName(FContext.Current.Key));
    StartAttachment(Self, mDownload, mUrl,
      TPath.Combine(mFolder, TAtlasIssuePreview.SafeFileName(AAttachment.Name)),
      TAtlasIssuePreview.SafeFileName(AAttachment.Name));
  end;
end;

end.
