unit Atlas.IDE.CodeInsight.Adapters.BuildNotifications;

// Bewertung eines Builds (#530) an die Benachrichtigungszentrale (#601): TAtlasNotificationsVerdictListener erfüllt
// IAtlasBuildVerdictListener (Atlas.Core.Build.Contract) für das Modul Build-Pipeline bzw. die Bewertung nur nach
// dem Compiler (Modul aus). Die Benachrichtigungszentrale lebt kürzer als die Compile-Ereignisse; die
// Kompositionswurzel (Atlas.IDE.CodeInsight.Composition.Build) reicht sie über ANotifications herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Build.Contract,
  Atlas.IDE.Notifications.Service;

type
  TAtlasNotificationsVerdictListener = class(TInterfacedObject, IAtlasBuildVerdictListener)
  private
    FNotifications: TFunc<TAtlasIdeNotifications>;
  public
    constructor Create(const ANotifications: TFunc<TAtlasIdeNotifications>);
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard;

{ TAtlasNotificationsVerdictListener }

constructor TAtlasNotificationsVerdictListener.Create(const ANotifications: TFunc<TAtlasIdeNotifications>);
begin
  inherited Create;
  FNotifications := ANotifications;
end;

procedure TAtlasNotificationsVerdictListener.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
var
  mNotifications: TFunc<TAtlasIdeNotifications>;
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mVerdict: TAtlasBuildVerdict;
begin
  if FNotifications() = nil then
  begin
    Exit;
  end;
  mNotifications := FNotifications;
  mMessages := AMessages;
  mProject := AProject;
  mVerdict := AVerdict;
  TAtlasGuard.Run(TAtlasFeature.Notifications,
    procedure
    var
      mCenter: TAtlasIdeNotifications;
    begin
      mCenter := mNotifications();
      if mCenter <> nil then
      begin
        mCenter.BuildEvaluated(mMessages, mProject, mVerdict);
      end;
    end);
end;

end.
