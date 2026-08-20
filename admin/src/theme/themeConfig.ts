import type { ThemeConfig } from 'antd';

// Deliberately neutral/professional — slate blue-gray, not the consumer
// app's rose/red branding (Vivaha's #D9467E). An admin/ops tool should
// read as distinct from the product it's administering.
export const themeConfig: ThemeConfig = {
  token: {
    colorPrimary: '#3457D5',
    colorInfo: '#3457D5',
    colorLink: '#3457D5',
    borderRadius: 6,
    fontFamily:
      "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
  },
  components: {
    Layout: {
      siderBg: '#1F2937',
      headerBg: '#ffffff',
      bodyBg: '#F5F6F8',
    },
    Menu: {
      darkItemBg: '#1F2937',
      darkItemSelectedBg: '#3457D5',
    },
  },
};
