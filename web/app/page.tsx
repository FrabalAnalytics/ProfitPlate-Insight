const managementQuestions = [
  "Where are we making money?",
  "Where are we losing money?",
  "What decisions should we make to improve profitability?",
];

export default function Home() {
  return (
    <main className="flex-1 bg-background px-6 py-12 font-sans text-foreground sm:px-10 sm:py-20">
      <article className="mx-auto max-w-5xl overflow-hidden rounded-2xl border border-border bg-surface">
        <header className="border-b border-border bg-brand-deep px-6 py-10 sm:px-12 sm:py-12">
          <div aria-hidden="true" className="mb-6 h-1 w-12 rounded-full bg-accent" />
          <h1 className="text-4xl font-semibold tracking-tight text-brand-foreground sm:text-5xl">
            ProfitPlate Insight
          </h1>
          <p className="mt-4 max-w-2xl text-lg leading-7 text-surface-muted sm:text-xl">
            Restaurant Profitability &amp; Executive Decision Intelligence Platform
          </p>
        </header>

        <div className="space-y-6 px-6 py-8 text-base leading-8 sm:px-12 sm:py-10">
          <p>
            <strong className="font-semibold">
              ProfitPlate Insight is a cloud-based restaurant profitability and
              business intelligence platform designed to help restaurant owners,
              CEOs, and management teams understand their true operating costs,
              monitor financial performance, identify profit leakages, and make
              better business decisions.
            </strong>
          </p>
          <p>
            Unlike traditional restaurant management software that focuses
            primarily on recording transactions, ProfitPlate Insight focuses on
            what those transactions mean for business profitability.
          </p>
          <p>
            The platform connects restaurant sales, recipes, ingredient costs,
            procurement, menu pricing, inventory activity, and relevant operating
            expenses to provide a clearer picture of business performance.
          </p>
          <p>
            It converts operational and financial data into practical intelligence
            that helps management answer three important questions:
          </p>
          <ul className="list-disc space-y-3 rounded-xl border border-border bg-surface-muted py-6 pr-6 pl-12 font-medium text-brand marker:text-brand sm:pr-8 sm:pl-14">
            {managementQuestions.map((question) => (
              <li key={question}>{question}</li>
            ))}
          </ul>
        </div>
      </article>
    </main>
  );
}
