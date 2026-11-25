unit Atlas.IDE.Tracker.Adapters.Review;

// „Prüfen“ (#2126), Rolle Adapters: TAtlasReviewTestsListener erfüllt
// IAtlasTestsListener aus Atlas.IDE.Base.Foundation.Tests und meldet das Ende der
// betroffenen Tests an TAtlasIdeIssueReview (Atlas.IDE.Tracker.Review).
// Anlegen und Anmelden nur in der Komposition des Moduls. Hauptthread.

interface

uses
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Tracker.Review;

type
  /// <summary>Ende der Testläufe an AReview.</summary>
  TAtlasReviewTestsListener = class(TInterfacedObject, IAtlasTestsListener)
  private
    FReview: TAtlasIdeIssueReview;
    FReviewRef: IInterface;
  public
    constructor Create(AReview: TAtlasIdeIssueReview);
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
  end;

implementation

{ TAtlasReviewTestsListener }

constructor TAtlasReviewTestsListener.Create(AReview: TAtlasIdeIssueReview);
begin
  inherited Create;
  FReview := AReview;
  FReviewRef := AReview;
end;

procedure TAtlasReviewTestsListener.TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
begin
  // Welches Testprojekt lief, spielt für „Prüfen“ keine Rolle: Es wartet nur auf den einen Lauf.
  FReview.TestsFinished(APassed, AFailed);
end;

end.
