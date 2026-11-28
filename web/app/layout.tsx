import {EmailSessionCapture} from "@/app/components/email-session-capture";
import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import "./components/data-table.css";
import "./components/material-picker.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "ProfitPlate Insights | Restaurant Profitability & Executive Intelligence",
  description:
    "Understand restaurant operating costs, monitor financial performance, identify profit leakages, and make better business decisions with ProfitPlate Insights.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      {/* Browser extensions can add body attributes before React hydrates.
          Limit the exception to this element; child mismatches still warn. */}
      <body suppressHydrationWarning className="min-h-full flex flex-col"><EmailSessionCapture/>{children}</body>
    </html>
  );
}
