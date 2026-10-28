unit Atlas.Core.Tracker.Internals.GitHubApi;

// Adresse der GitHub-REST-API (#765, #1268), ohne Netz und daher testbar:
// github.com → https://api.github.com, GitHub Enterprise → <Server>/api/v3.
// Der Anbieter (Providers.GitHub) und „Issue anlegen“ (NewIssue) bauen ihre
// Adressen beide hierauf, damit Enterprise überall gleich behandelt wird.

interface

uses
  Atlas.Core.Tracker.Contract;

type
  TAtlasGitHubApi = class
  public const
    ApiHost = 'https://api.github.com';
  public
    /// <summary>Basis der REST-API; '' ohne gültigen Server.</summary>
    class function Base(const ATarget: TAtlasTrackerTarget): string; static;
  end;

implementation

class function TAtlasGitHubApi.Base(const ATarget: TAtlasTrackerTarget): string;
var
  mServer: string;
begin
  mServer := ATarget.Server;
  if mServer = '' then
    Exit('');
  if (mServer = 'https://github.com') or (mServer = 'https://www.github.com') then
    Result := ApiHost
  else
    Result := mServer + '/api/v3';
end;

end.
