import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/utils";

const buttonVariants = cva(
  "inline-flex min-h-10 items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-medium transition-colors focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand disabled:pointer-events-none disabled:opacity-50",
  { variants: { variant: {
    default: "bg-brand text-white hover:bg-brand-deep",
    outline: "border border-border bg-white text-foreground hover:bg-surface-muted",
    ghost: "text-foreground hover:bg-surface-muted",
  } }, defaultVariants: { variant: "default" } },
);
export function Button({ className, variant, asChild = false, ...props }:
  React.ComponentProps<"button"> & VariantProps<typeof buttonVariants> & { asChild?: boolean }) {
  const Component = asChild ? Slot : "button";
  return <Component data-slot="button" className={cn(buttonVariants({ variant }), className)} {...props} />;
}
