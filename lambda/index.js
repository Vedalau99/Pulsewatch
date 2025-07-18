exports.handler = async (event) => {
  return {
    statusCode: 200,
    body: JSON.stringify({ message: "PulseWatch Lambda is alive!" }),
  };
};
